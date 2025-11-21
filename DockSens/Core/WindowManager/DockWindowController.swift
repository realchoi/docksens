//
//  DockWindowController.swift
//  DockSens
//
//  Created by DockSens Team.
//

import AppKit
import ApplicationServices

/// 负责处理 Dock 点击的窗口操作逻辑
@MainActor
final class DockWindowController {

    private let windowActivator = WindowActivator()

    /// 处理 Dock 图标点击
    /// - Parameters:
    ///   - icon: 被点击的 Dock 图标
    ///   - windows: 该应用的所有窗口
    ///   - frontmostPIDBeforeClick: 点击前的前台应用 PID（用于准确判断应用是否已在前台）
    func handleDockClick(for icon: DockIconInfo, windows: [WindowInfo], frontmostPIDBeforeClick: pid_t) async {
        print("🎯 DockWindowController: 处理 '\(icon.title)' 的点击，窗口数量: \(windows.count)")

        // 1. 检查窗口数量
        guard !windows.isEmpty else {
            print("⏭️ DockWindowController: 应用没有窗口，尝试启动应用")
            // 尝试通过 URL 启动应用
            if let url = icon.url {
                Task {
                    try? await NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                }
            }
            return
        }

        // 2. 如果有多个窗口，让悬浮预览来处理（不执行最小化/激活）
        if windows.count > 1 {
            print("📋 DockWindowController: 应用有多个窗口，跳过（由悬浮预览处理）")
            return
        }

        // 3. 单窗口逻辑：检查窗口状态
        guard let window = windows.first else { return }

        // 4. 🔧 优先检查最小化状态
        if window.isMinimized {
            print("🔼 DockWindowController: 窗口已最小化，执行激活")
            await windowActivator.activateWindow(window)
            return
        }

        // 5. 🔧 关键修复：使用点击前的前台应用 PID 进行判断
        let isPIDMatch = (frontmostPIDBeforeClick == window.pid)

        print("🔍 DockWindowController: 点击前前台应用 PID=\(frontmostPIDBeforeClick), 目标应用 PID=\(window.pid), 匹配=\(isPIDMatch)")

        if !isPIDMatch {
            // 情况 A：应用不在前台 → 激活
            print("🎯 DockWindowController: 应用不在前台，执行激活")
            await windowActivator.activateWindow(window)
            return
        }

        // 6. 🔧 优化：应用已在前台，状态已稳定，直接检查焦点（移除不必要的 50ms 等待）
        // 因为通过点击前 PID 判断，应用已确定在前台，无需等待状态稳定
        let isFocusedWindow = await checkIfWindowIsFocused(window)

        if isFocusedWindow {
            // 情况 B：窗口是焦点 → 最小化
            print("🔽 DockWindowController: 窗口是焦点，执行最小化")
            minimizeWindow(window)
        } else {
            // 情况 C：窗口存在但不是焦点 → 激活
            print("🎯 DockWindowController: 窗口不是焦点，执行激活")
            await windowActivator.activateWindow(window)
        }
    }

    /// 🔧 修复：检查窗口是否真的是焦点窗口
    private func checkIfWindowIsFocused(_ window: WindowInfo) async -> Bool {
        return await Task.detached {
            // 1. 首先检查应用是否是前台应用
            let currentApp = NSWorkspace.shared.frontmostApplication
            guard currentApp?.processIdentifier == window.pid else {
                print("🔍 DockWindowController: 应用不是前台应用 (PID: \(window.pid) vs 前台: \(currentApp?.processIdentifier ?? -1))")
                return false
            }

            let appRef = AXUIElementCreateApplication(window.pid)

            // 2. 获取焦点窗口
            var focusedWindowRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &focusedWindowRef) == .success else {
                print("⚠️ DockWindowController: 无法获取焦点窗口")
                return false
            }

            // 将 CFTypeRef 强制转换为 AXUIElement
            let focusedWindow = focusedWindowRef as! AXUIElement

            // 3. 获取焦点窗口的标题
            var titleRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(focusedWindow, kAXTitleAttribute as CFString, &titleRef) == .success,
                  let title = titleRef as? String else {
                print("⚠️ DockWindowController: 无法获取焦点窗口标题")
                return false
            }

            // 4. 比较标题（考虑到标题可能为空）
            let isFocused = (title == window.title) || (title.isEmpty && window.title.isEmpty)
            print("🔍 DockWindowController: 焦点窗口='\(title)', 目标窗口='\(window.title)', 匹配=\(isFocused)")

            return isFocused
        }.value
    }

    /// 最小化窗口
    private func minimizeWindow(_ window: WindowInfo) {
        Task.detached {
            let appRef = AXUIElementCreateApplication(window.pid)
            var windowsRef: CFTypeRef?

            guard AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef) == .success else {
                print("⚠️ DockWindowController: 无法获取应用 \(window.pid) 的窗口列表")
                return
            }

            guard let windowList = windowsRef as? [AXUIElement] else {
                print("⚠️ DockWindowController: 窗口列表类型转换失败")
                return
            }

            // 匹配目标窗口
            let match = windowList.first { axWindow in
                var titleRef: CFTypeRef?

                // 1. 标题匹配
                if AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef) == .success,
                   let t = titleRef as? String, t == window.title {

                    // 2. 位置匹配（可选，更精确）
                    if let posValue = Self.getAXAttribute(axWindow, kAXPositionAttribute, ofType: AXValue.self),
                       let sizeValue = Self.getAXAttribute(axWindow, kAXSizeAttribute, ofType: AXValue.self) {

                        var pos = CGPoint.zero
                        var size = CGSize.zero
                        AXValueGetValue(posValue, .cgPoint, &pos)
                        AXValueGetValue(sizeValue, .cgSize, &size)

                        let axCenter = CGPoint(x: pos.x + size.width / 2, y: pos.y + size.height / 2)
                        let targetCenter = CGPoint(x: window.frame.midX, y: window.frame.midY)
                        let dist = hypot(axCenter.x - targetCenter.x, axCenter.y - targetCenter.y)

                        if dist < 100 { return true }
                    } else {
                        // 标题一致，认为匹配
                        return true
                    }
                }
                return false
            }

            if let targetWindow = match ?? windowList.first {
                // 设置最小化属性
                let result = AXUIElementSetAttributeValue(targetWindow, kAXMinimizedAttribute as CFString, true as CFTypeRef)

                if result == .success {
                    print("✅ DockWindowController: 成功最小化窗口 '\(window.title)'")
                } else {
                    print("⚠️ DockWindowController: 最小化失败，错误码: \(result.rawValue)")
                }
            } else {
                print("⚠️ DockWindowController: 未找到匹配的窗口 '\(window.title)'")
            }
        }
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
            return value as? T
        }
        return nil
    }
}
