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

    // MARK: - Private Properties
    private var eventMonitor: Any?
    private let hoverDetector: DockHoverDetector

    init(hoverDetector: DockHoverDetector) {
        self.hoverDetector = hoverDetector
    }

    // MARK: - Public Methods

    func startMonitoring() {
        // 注册全局鼠标点击监听
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            self?.handleMouseClick(event)
        }
        print("🖱️ DockClickDetector: 开始监听 Dock 点击事件")
    }

    func stopMonitoring() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        print("🖱️ DockClickDetector: 停止监听 Dock 点击事件")
    }

    // MARK: - Logic

    private func handleMouseClick(_ event: NSEvent) {
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

        // 使用 hoverDetector 的缓存图标列表进行命中测试
        // 注意：这里我们需要访问 DockHoverDetector 的 cachedIcons
        // 由于 cachedIcons 是私有的，我们需要修改 DockHoverDetector 或使用另一种方式

        // 临时方案：直接扫描 Dock 图标
        Task {
            let icons = await scanDockIcons()
            if let hitIcon = icons.first(where: { $0.frame.contains(clickPointTopLeft) }) {
                print("🎯 DockClickDetector: 检测到点击 Dock 图标 '\(hitIcon.title)'")

                // 🔧 修复：设置 clickedIcon
                self.clickedIcon = hitIcon

                // 🔧 修复：不立即清除，让 AppState 有时间读取
                // AppState 会在处理完后自动检测到下一次不同的点击
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
            guard let children = self.getAXAttribute(dockRef, kAXChildrenAttribute, ofType: [AXUIElement].self) else {
                return []
            }

            for child in children {
                let role = self.getAXAttribute(child, kAXRoleAttribute, ofType: String.self)
                if role == "AXList" {
                    guard let iconElements = self.getAXAttribute(child, kAXChildrenAttribute, ofType: [AXUIElement].self) else {
                        continue
                    }
                    for iconRef in iconElements {
                        if let info = self.extractDockIconInfo(iconRef) {
                            icons.append(info)
                        }
                    }
                }
            }
            return icons
        }.value
    }

    private nonisolated func extractDockIconInfo(_ element: AXUIElement) -> DockIconInfo? {
        let title = getAXAttribute(element, kAXTitleAttribute, ofType: String.self) ?? "Unknown"
        let role = getAXAttribute(element, kAXRoleAttribute, ofType: String.self)
        if role != "AXDockItem" { return nil }

        var frame = CGRect.zero
        if let posValue = getAXAttribute(element, kAXPositionAttribute, ofType: AXValue.self),
           let sizeValue = getAXAttribute(element, kAXSizeAttribute, ofType: AXValue.self) {
            var pos = CGPoint.zero
            var size = CGSize.zero
            AXValueGetValue(posValue, .cgPoint, &pos)
            AXValueGetValue(sizeValue, .cgSize, &size)
            frame = CGRect(origin: pos, size: size)
        }

        var url: URL? = nil
        if let urlString = getAXAttribute(element, kAXURLAttribute, ofType: String.self) {
            url = URL(string: urlString)
        } else if let urlRef = getAXAttribute(element, kAXURLAttribute, ofType: URL.self) {
            url = urlRef
        }

        return DockIconInfo(id: Int(frame.origin.x), title: title, frame: frame, url: url)
    }

    private nonisolated func getAXAttribute<T>(_ element: AXUIElement, _ attribute: String, ofType type: T.Type) -> T? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        if result == .success, let value = value {
            if T.self == AXValue.self { return value as? T }
            if T.self == String.self { return value as? T }
            if T.self == [AXUIElement].self { return value as? T }
            if T.self == Bool.self { return value as? T }
            if T.self == URL.self { return value as? T }
            return value as? T
        }
        return nil
    }
}
