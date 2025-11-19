//
//  DockHoverDetector.swift
//  DockSens
//
//  Created by DockSens Team.
//

import AppKit
import Combine

/// 负责检测鼠标是否悬停在 Dock 图标上
@MainActor
class DockHoverDetector: ObservableObject {
    
    // MARK: - Published State
    @Published var hoveredIcon: DockIconInfo? = nil
    @Published var isHovering: Bool = false
    
    // MARK: - Private Properties
    private var eventMonitor: Any?
    private var cachedIcons: [DockIconInfo] = []
    private let engine: WindowEngine
    
    // FIX: 使用 Task 替代 Timer，解决 Swift 6 "Reference to captured var self" 并发警告
    private var hoverTask: Task<Void, Never>?
    
    init(engine: WindowEngine) {
        self.engine = engine
    }
    
    // MARK: - Public Methods
    
    func startMonitoring() {
        // 1. 初始扫描布局 (这是一个耗时操作，实际应用应监听显示器变化来触发更新)
        Task {
            self.cachedIcons = await engine.scanDockIcons()
            print("DockHoverDetector: Cached \(self.cachedIcons.count) icons")
        }
        
        // 2. 注册全局鼠标移动监听
        // NSEvent.addGlobalMonitorForEvents 仅当 App 处于后台时生效
        // 如果需要前台也能生效，需结合 addLocalMonitorForEvents
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            self?.handleMouseMove(event)
        }
    }
    
    func stopMonitoring() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        hoverTask?.cancel()
    }
    
    // MARK: - Logic
    
    private func handleMouseMove(_ event: NSEvent) {
        // 获取屏幕坐标 (Cocoa 坐标系，原点在左下角)
        guard let screen = NSScreen.main else { return }
        let mouseLocation = NSEvent.mouseLocation
        let screenHeight = screen.frame.height
        
        // 翻转 Y 轴以匹配 AX 坐标 (Top-Left)
        let mousePointTopLeft = CGPoint(x: mouseLocation.x, y: screenHeight - mouseLocation.y)
        
        // 简单的命中测试优化：首先检查 Y 轴是否在 Dock 区域
        // 假设 Dock 高度不超过 150pt
        if mousePointTopLeft.y < (screenHeight - 150) {
            if isHovering { resetHover() }
            return
        }
        
        // 遍历缓存的图标进行命中测试
        if let hitIcon = cachedIcons.first(where: { $0.frame.contains(mousePointTopLeft) }) {
            if hoveredIcon?.id != hitIcon.id {
                // 发现了新图标，启动防抖计时器
                startHoverTimer(for: hitIcon)
            }
        } else {
            resetHover()
        }
    }
    
    private func startHoverTimer(for icon: DockIconInfo) {
        // 1. 取消上一次的等待任务
        hoverTask?.cancel()
        
        // 2. 开启新任务
        // 因为当前方法在 @MainActor 中，Task 也会自动继承 @MainActor 上下文，
        // 所以在 Task 内部访问 self 是完全线程安全的，不会有 Swift 6 警告。
        hoverTask = Task {
            do {
                // 延时 0.2秒 (macOS 13+ API)
                try await Task.sleep(for: .seconds(0.2))
                
                // 检查任务是否被取消 (例如鼠标移开了)
                guard !Task.isCancelled else { return }
                
                self.hoveredIcon = icon
                self.isHovering = true
            } catch {
                // 任务被取消时会抛出 CancellationError，可以在此忽略
            }
        }
    }
    
    private func resetHover() {
        // 取消正在进行的悬停判定
        hoverTask?.cancel()
        
        if isHovering {
            hoveredIcon = nil
            isHovering = false
        }
    }
}