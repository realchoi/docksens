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
    @Published var rightClickedIcon: DockIconInfo? = nil // 🔧 新增：右键点击状态

    // MARK: - Private Properties
    private var leftClickMonitor: Any?
    private var rightClickMonitor: Any?
    private let hoverDetector: DockHoverDetector

    init(hoverDetector: DockHoverDetector) {
        self.hoverDetector = hoverDetector
    }

    // MARK: - Public Methods

    func startMonitoring() {
        // 监听左键点击
        leftClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            self?.handleClick(event, isRightClick: false)
        }
        
        // 🔧 修复：监听右键点击，以便在打开 Dock 菜单时隐藏预览窗口
        rightClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            self?.handleClick(event, isRightClick: true)
        }
        print("🖱️ DockClickDetector: 开始监听 Dock 点击事件")
    }

    func stopMonitoring() {
        if let monitor = leftClickMonitor {
            NSEvent.removeMonitor(monitor)
            leftClickMonitor = nil
        }
        // 移除右键监听
        if let monitor = rightClickMonitor {
            NSEvent.removeMonitor(monitor)
            rightClickMonitor = nil
        }
        print("🖱️ DockClickDetector: 停止监听 Dock 点击事件")
    }

    // MARK: - Logic

    private func handleClick(_ event: NSEvent, isRightClick: Bool) { // 重命名为 handleClick
        // 获取点击位置 (Cocoa 坐标系)
        guard let screen = NSScreen.main else { return }
        let clickLocation = NSEvent.mouseLocation
        let screenHeight = screen.frame.height

        // 转换为 Quartz 坐标系 (Top-Left)
        let clickPointTopLeft = CGPoint(x: clickLocation.x, y: screenHeight - clickLocation.y)

        // 检查是否在 Dock 区域 (底部 150pt)
        if clickPointTopLeft.y < (screenHeight - 150) {
            return // 不在 Dock 区域
        }

        // 临时方案：直接扫描 Dock 图标
        Task {
            let icons = await scanDockIcons()
            if let hitIcon = icons.first(where: { $0.frame.contains(clickPointTopLeft) }) {
                print("🎯 DockClickDetector: 检测到\(isRightClick ? "右键" : "左键")点击 Dock 图标 '\(hitIcon.title)'")

                // 🔧 修复：根据点击类型设置不同的状态
                if isRightClick {
                    self.rightClickedIcon = hitIcon
                } else {
                    self.clickedIcon = hitIcon
                }
            }
        }
    }

    // 临时方案：扫描 Dock 图标
    // TODO: 优化 - 复用 DockHoverDetector 的缓存
    private func scanDockIcons() async -> [DockIconInfo] {
        return await Task.detached {
            var icons: [DockIconInfo] = []

            let dockApps = NSWorkspace.shared.runningApplications.filter {
                $0.bundleIdentifier == "com.apple.dock"
            }
            guard let dockApp = dockApps.first else { return [] }

            let dockRef = AXUIElementCreateApplication(dockApp.processIdentifier)
            guard let children = AXUtils.getAXAttribute(dockRef, kAXChildrenAttribute, ofType: [AXUIElement].self) else {
                return []
            }

            for child in children {
                let role = AXUtils.getAXAttribute(child, kAXRoleAttribute, ofType: String.self)
                if role == "AXList" {
                    guard let iconElements = AXUtils.getAXAttribute(child, kAXChildrenAttribute, ofType: [AXUIElement].self) else {
                        continue
                    }
                    for iconRef in iconElements {
                        if let info = AXUtils.extractDockIconInfo(iconRef) {
                            icons.append(info)
                        }
                    }
                }
            }
            return icons
        }.value
    }
}
