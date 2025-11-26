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
    // 移除本地 cachedIcons，改用 dockMonitor.icons
    // private var cachedIcons: [DockIconInfo] = []
    private let dockMonitor: DockMonitor
    private var cancellables = Set<AnyCancellable>()

    // FIX: 使用 Task 替代 Timer，解决 Swift 6 "Reference to captured var self" 并发警告
    private var hoverTask: Task<Void, Never>?

    // 🔧 修复：添加暂停状态，点击后暂停悬停检测
    private var isPaused: Bool = false
    private var lastMousePosition: CGPoint = .zero
    
    init(dockMonitor: DockMonitor) {
        self.dockMonitor = dockMonitor
    }
    
    // MARK: - Public Methods
    
    func startMonitoring() {
        // 1. 监听 DockMonitor 的图标更新
        // 注意：这里不需要手动赋值 cachedIcons，直接在 handleMouseMove 中访问 dockMonitor.icons 即可
        // 或者如果为了性能考虑，可以在这里订阅并更新本地缓存（但 DockMonitor 已经在 MainActor，直接访问很快）
        
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
        cancellables.removeAll()
    }

    // 🔧 修复：暂停悬停检测（点击后调用）
    func pauseHoverDetection() {
        isPaused = true
        lastMousePosition = NSEvent.mouseLocation
        print("🔇 DockHoverDetector: 暂停悬停检测")
    }

    // 🔧 修复：恢复悬停检测（鼠标移动后自动调用）
    private func resumeHoverDetection() {
        isPaused = false
        print("🔊 DockHoverDetector: 恢复悬停检测")
    }
    
    // 🔧 新增：允许外部显式控制暂停（用于预览窗口交互时）
    func setExplicitlyPaused(_ paused: Bool) {
        if paused {
            isPaused = true
            // 取消当前的悬停状态
            resetHover()
        } else {
            isPaused = false
            // 重置位置以避免立即触发自动恢复逻辑（如果需要）
            lastMousePosition = NSEvent.mouseLocation
        }
    }
    
    // MARK: - Logic
    
    private func handleMouseMove(_ event: NSEvent) {
        // 🔧 修复：如果暂停了，检查鼠标是否移动
        if isPaused {
            let currentPosition = NSEvent.mouseLocation
            let distance = hypot(currentPosition.x - lastMousePosition.x, currentPosition.y - lastMousePosition.y)

            // 如果鼠标移动超过 10pt，恢复悬停检测
            if distance > 10 {
                resumeHoverDetection()
            } else {
                // 鼠标没有移动足够的距离，继续暂停
                return
            }
        }

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

        // 遍历 DockMonitor 的图标进行命中测试
        // 直接使用 dockMonitor.icons，因为都在 MainActor 上
        if let hitIcon = dockMonitor.icons.first(where: { $0.frame.contains(mousePointTopLeft) }) {
            if hoveredIcon?.id != hitIcon.id {
                // 发现了新图标，启动防抖计时器
                startHoverTimer(for: hitIcon)
            }
        } else {
            // 🔧 修复：如果在 Dock 区域深处（例如底部 50pt）但没有匹配到图标，
            // 可能是因为 Dock 布局改变（如放大）导致缓存失效。
            // 此时强制刷新 DockMonitor。
            if mousePointTopLeft.y > (screenHeight - 50) {
                // 限制刷新频率，避免每帧都刷新
                // DockMonitor.refresh() 内部已经有防抖，所以这里可以直接调用
                dockMonitor.refresh()
            }
            
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