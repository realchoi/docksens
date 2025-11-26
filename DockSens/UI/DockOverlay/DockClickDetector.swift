//
//  DockClickDetector.swift
//  DockSens
//
//  Created by DockSens Team.
//

import AppKit
import Combine

/// 负责检测鼠标在 Dock 图标上的点击事件
@MainActor
class DockClickDetector: ObservableObject {

    // MARK: - Published State
    @Published var clickedIcon: DockIconInfo? = nil
    @Published var rightClickedIcon: DockIconInfo? = nil
    
    // 🔧 新增：分离按下和松开事件，用于解决最小化/恢复冲突
    @Published var mouseDownIcon: DockIconInfo? = nil
    @Published var mouseUpIcon: DockIconInfo? = nil

    // MARK: - Private Properties
    private var leftMouseDownMonitor: Any?
    private var leftMouseUpMonitor: Any?
    private var rightClickMonitor: Any?
    private let hoverDetector: DockHoverDetector
    private let dockMonitor: DockMonitor

    init(hoverDetector: DockHoverDetector, dockMonitor: DockMonitor) {
        self.hoverDetector = hoverDetector
        self.dockMonitor = dockMonitor
    }

    // MARK: - Public Methods

    func startMonitoring() {
        // 1. 监听左键按下 (用于判断意图)
        leftMouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            self?.handleLeftClick(event, phase: .down)
        }
        
        // 2. 监听左键松开 (用于执行操作)
        leftMouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            self?.handleLeftClick(event, phase: .up)
        }
        
        // 3. 监听右键点击
        rightClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            self?.handleRightClick(event)
        }
        print("🖱️ DockClickDetector: 开始监听 Dock 点击事件")
    }

    func stopMonitoring() {
        if let monitor = leftMouseDownMonitor { NSEvent.removeMonitor(monitor); leftMouseDownMonitor = nil }
        if let monitor = leftMouseUpMonitor { NSEvent.removeMonitor(monitor); leftMouseUpMonitor = nil }
        if let monitor = rightClickMonitor { NSEvent.removeMonitor(monitor); rightClickMonitor = nil }
        print("🖱️ DockClickDetector: 停止监听 Dock 点击事件")
    }

    // MARK: - Logic
    
    private enum ClickPhase { case down, up }

    private func handleLeftClick(_ event: NSEvent, phase: ClickPhase) {
        let clickPointTopLeft = getClickPoint(event)
        guard isPointInDock(clickPointTopLeft) else { return }

        if let hitIcon = dockMonitor.icons.first(where: { $0.frame.contains(clickPointTopLeft) }) {
            // print("🎯 DockClickDetector: 左键 \(phase) '\(hitIcon.title)'")
            if phase == .down {
                self.mouseDownIcon = hitIcon
            } else {
                self.mouseUpIcon = hitIcon
                // 兼容旧逻辑 (虽然 AppState 将主要使用 Up/Down，但为了保险保留 clickedIcon)
                self.clickedIcon = hitIcon
            }
        }
    }
    
    private func handleRightClick(_ event: NSEvent) {
        let clickPointTopLeft = getClickPoint(event)
        guard isPointInDock(clickPointTopLeft) else { return }
        
        if let hitIcon = dockMonitor.icons.first(where: { $0.frame.contains(clickPointTopLeft) }) {
            self.rightClickedIcon = hitIcon
        }
    }
    
    private func getClickPoint(_ event: NSEvent) -> CGPoint {
        guard let screen = NSScreen.main else { return .zero }
        let clickLocation = NSEvent.mouseLocation
        return CGPoint(x: clickLocation.x, y: screen.frame.height - clickLocation.y)
    }
    
    private func isPointInDock(_ point: CGPoint) -> Bool {
        guard let screen = NSScreen.main else { return false }
        return point.y > (screen.frame.height - 150)
    }
}
