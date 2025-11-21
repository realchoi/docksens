//
//  WindowActivator.swift
//  DockSens
//
//  Created by DockSens Team.
//

import AppKit
import ApplicationServices

/// 负责激活和还原窗口
final class WindowActivator {

    /// 激活指定的窗口（复用 SwitcherWindow 的逻辑）
    func activateWindow(_ window: WindowInfo) async {
        // 1. 激活应用程序
        guard let app = NSRunningApplication(processIdentifier: window.pid) else {
            print("⚠️ WindowActivator: 无法找到 PID \(window.pid) 对应的应用")
            return
        }

        // macOS 14+ API: 让出激活权
        if #available(macOS 14.0, *) {
            NSApp.yieldActivation(to: app)
        }

        // 激活应用（包含所有窗口，忽略其他应用）
        let rawOptions: UInt = (1 << 0) | (1 << 1)
        let options = NSApplication.ActivationOptions(rawValue: rawOptions)
        app.activate(options: options)

        // 等待激活生效
        try? await Task.sleep(for: .milliseconds(50))

        // 2. 使用 AX API 提升窗口
        await performAXRaise(window)
    }

    /// 使用 Accessibility API 提升窗口到前台
    private func performAXRaise(_ window: WindowInfo) async {
        let pid = window.pid
        let targetTitle = window.title
        let targetFrame = window.frame

        await Task.detached {
            let appRef = AXUIElementCreateApplication(pid)
            var windowsRef: CFTypeRef?

            // 获取应用的所有窗口
            guard AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef) == .success else {
                print("⚠️ WindowActivator: 无法获取应用 \(pid) 的窗口列表")
                return
            }

            guard let windowList = windowsRef as? [AXUIElement] else {
                print("⚠️ WindowActivator: 窗口列表类型转换失败")
                return
            }

            // 匹配目标窗口
            let match = windowList.first { axWindow in
                var titleRef: CFTypeRef?

                // 1. 标题匹配
                if AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef) == .success,
                   let t = titleRef as? String, t == targetTitle {

                    // 2. 尺寸位置匹配（放宽容差到 100pt）
                    if let posValue = Self.getAXAttribute(axWindow, kAXPositionAttribute as String, ofType: AXValue.self),
                       let sizeValue = Self.getAXAttribute(axWindow, kAXSizeAttribute as String, ofType: AXValue.self) {

                        var pos = CGPoint.zero
                        var size = CGSize.zero
                        AXValueGetValue(posValue, .cgPoint, &pos)
                        AXValueGetValue(sizeValue, .cgSize, &size)

                        let axCenter = CGPoint(x: pos.x + size.width / 2, y: pos.y + size.height / 2)
                        let targetCenter = CGPoint(x: targetFrame.midX, y: targetFrame.midY)
                        let dist = hypot(axCenter.x - targetCenter.x, axCenter.y - targetCenter.y)

                        // 容差 100pt，确保即使 AX/SCK 坐标有偏差也能命中
                        if dist < 100 { return true }
                    } else {
                        // 无法获取 Frame，但标题一致，认为匹配
                        return true
                    }
                }
                return false
            }

            if let targetWindow = match ?? windowList.first {
                // 还原最小化窗口
                var minimizedRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(targetWindow, kAXMinimizedAttribute as CFString, &minimizedRef) == .success,
                   let minimized = minimizedRef as? Bool, minimized == true {
                    AXUIElementSetAttributeValue(targetWindow, kAXMinimizedAttribute as CFString, false as CFTypeRef)
                    print("✅ WindowActivator: 还原最小化窗口 '\(targetTitle)'")
                }

                // 激活窗口
                AXUIElementPerformAction(targetWindow, kAXRaiseAction as CFString)
                AXUIElementSetAttributeValue(targetWindow, kAXMainAttribute as CFString, true as CFTypeRef)
                AXUIElementSetAttributeValue(targetWindow, kAXFocusedAttribute as CFString, true as CFTypeRef)

                print("✅ WindowActivator: 激活窗口 '\(targetTitle)'")
            } else {
                print("⚠️ WindowActivator: 未找到匹配的窗口 '\(targetTitle)'")
            }
        }.value
    }

    // MARK: - Helper Methods

    private static nonisolated func getAXAttribute<T>(_ element: AXUIElement, _ attribute: String, ofType type: T.Type) -> T? {
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
