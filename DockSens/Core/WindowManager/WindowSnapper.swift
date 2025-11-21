//
//  WindowSnapper.swift
//  DockSens
//
//  Created by DockSens Team.
//

import AppKit
import ApplicationServices
import Foundation

enum SnapPosition {
    case left
    case right
    case maximize
    case center
}

final class WindowSnapper {
    // 防止重复触发的状态锁
    private var isSnapping = false
    private let lock = NSLock()

    func snapActiveWindow(to position: SnapPosition) {
        // 防止并发执行
        lock.lock()
        guard !isSnapping else {
            lock.unlock()
            return
        }
        isSnapping = true
        lock.unlock()

        defer {
            lock.lock()
            isSnapping = false
            lock.unlock()
        }

        // 1. 获取当前活跃窗口
        guard let focusedWindow = getFocusedWindow() else {
            print("⚠️ 无法获取焦点窗口")
            return
        }

        // 2. 获取当前窗口所在的屏幕
        guard let currentFrame = getWindowFrame(focusedWindow),
              let screen = getScreen(containing: currentFrame) else {
            print("⚠️ 无法获取窗口位置或屏幕")
            return
        }
        
        // 3. 坐标转换准备
        guard let primaryScreen = NSScreen.screens.first else { return }
        let primaryHeight = primaryScreen.frame.height
        let visibleFrameCocoa = screen.visibleFrame
        
        let axY = primaryHeight - (visibleFrameCocoa.origin.y + visibleFrameCocoa.height)
        let axVisibleFrame = CGRect(
            x: visibleFrameCocoa.origin.x,
            y: axY,
            width: visibleFrameCocoa.width,
            height: visibleFrameCocoa.height
        )
        
        // 4. 计算目标 Frame
        var targetFrame = axVisibleFrame
        
        switch position {
        case .left:
            targetFrame.size.width = axVisibleFrame.width / 2
        case .right:
            targetFrame.origin.x = axVisibleFrame.minX + axVisibleFrame.width / 2
            targetFrame.size.width = axVisibleFrame.width / 2
        case .maximize:
            break
        case .center:
            let width = axVisibleFrame.width * 0.8
            let height = axVisibleFrame.height * 0.8
            targetFrame = CGRect(
                x: axVisibleFrame.midX - width / 2,
                y: axVisibleFrame.midY - height / 2,
                width: width,
                height: height
            )
        }

        // 取整目标坐标，避免浮点数导致的不精确
        targetFrame = CGRect(
            x: round(targetFrame.origin.x),
            y: round(targetFrame.origin.y),
            width: round(targetFrame.size.width),
            height: round(targetFrame.size.height)
        )

        // 5. Rectangle 的完整策略：禁用 Enhanced UI，设置窗口，可选恢复
        setWindowFrame(focusedWindow, to: targetFrame)
    }
    
    // MARK: - Accessibility Helpers

    private func getApplicationName(for window: AXUIElement) -> String? {
        guard let app = getApplicationElement(for: window) else { return nil }

        var titleValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(app, kAXTitleAttribute as CFString, &titleValue)

        if result == .success, let title = titleValue as? String {
            return title
        }
        return nil
    }

    private func getFocusedWindow() -> AXUIElement? {
        // 方法 1: 使用 NSWorkspace 获取当前活跃应用（最可靠）
        if let runningApp = NSWorkspace.shared.frontmostApplication,
           let pid = runningApp.processIdentifier as pid_t? {
            let appElement = AXUIElementCreateApplication(pid)

            // 尝试获取焦点窗口
            var focusedWindow: CFTypeRef?
            let windowResult = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindow)

            if windowResult == .success {
                return (focusedWindow as! AXUIElement)
            }

            // 尝试获取主窗口
            var mainWindow: CFTypeRef?
            let mainResult = AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &mainWindow)

            if mainResult == .success {
                return (mainWindow as! AXUIElement)
            }

            // 尝试获取所有窗口
            var windowsRef: CFTypeRef?
            let windowsResult = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)

            if windowsResult == .success,
               let windows = windowsRef as? [AXUIElement],
               !windows.isEmpty {
                return windows.first
            }

            print("⚠️ 应用 \(runningApp.localizedName ?? "Unknown") 没有可访问的窗口")
        }

        // 方法 2: 传统的 Accessibility API 方法（备用）
        let systemWide = AXUIElementCreateSystemWide()
        var focusedApp: CFTypeRef?

        let result = AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &focusedApp)
        guard result == .success, let app = focusedApp else {
            return nil
        }

        let appElement = app as! AXUIElement

        // 尝试获取焦点窗口
        var focusedWindow: CFTypeRef?
        let windowResult = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindow)

        if windowResult == .success {
            return (focusedWindow as! AXUIElement)
        }

        // 尝试获取主窗口
        var mainWindow: CFTypeRef?
        let mainResult = AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &mainWindow)

        if mainResult == .success {
            return (mainWindow as! AXUIElement)
        }

        // 获取所有窗口
        var windowsRef: CFTypeRef?
        let windowsResult = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)

        if windowsResult == .success,
           let windows = windowsRef as? [AXUIElement],
           let firstWindow = windows.first {
            return firstWindow
        }

        return nil
    }
    
    private func getWindowFrame(_ window: AXUIElement) -> CGRect? {
        var posValue: CFTypeRef?
        var sizeValue: CFTypeRef?

        AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posValue)
        AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue)

        guard let posRef = posValue, CFGetTypeID(posRef) == AXValueGetTypeID(),
              let sizeRef = sizeValue, CFGetTypeID(sizeRef) == AXValueGetTypeID() else { return nil }

        let pos = posRef as! AXValue
        let size = sizeRef as! AXValue

        var point = CGPoint.zero
        var rectSize = CGSize.zero

        AXValueGetValue(pos, .cgPoint, &point)
        AXValueGetValue(size, .cgSize, &rectSize)

        return CGRect(origin: point, size: rectSize)
    }

    private func getMinimumSize(_ window: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(window, "AXMinSize" as CFString, &value)

        guard result == .success,
              let sizeValue = value,
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
            return nil
        }

        var size = CGSize.zero
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return size
    }

    private func getMaximumSize(_ window: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(window, "AXMaxSize" as CFString, &value)

        guard result == .success,
              let sizeValue = value,
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
            return nil
        }

        var size = CGSize.zero
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return size
    }

    // MARK: - Window Frame Setting

    /// 检查窗口属性是否可设置
    private func isAttributeSettable(_ element: AXUIElement, attribute: CFString) -> Bool {
        var settable: DarwinBoolean = false
        let result = AXUIElementIsAttributeSettable(element, attribute, &settable)
        return result == .success && settable.boolValue
    }

    /// Rectangle 的完整策略：禁用 Enhanced UI，设置窗口，可选恢复
    /// 这是防止应用窗口管理器干扰的关键
    private func setWindowFrame(_ window: AXUIElement, to rect: CGRect) {
        // 1. 检查窗口属性
        let canSetSize = isAttributeSettable(window, attribute: kAXSizeAttribute as CFString)

        // 2. 获取窗口的尺寸约束（对于不可调整大小的窗口）
        var adjustedRect = rect
        if !canSetSize {
            if let minSize = getMinimumSize(window), let maxSize = getMaximumSize(window) {
                adjustedRect.size.width = max(minSize.width, min(rect.size.width, maxSize.width))
                adjustedRect.size.height = max(minSize.height, min(rect.size.height, maxSize.height))
            }
        }

        // 3. 获取应用程序元素并保存 Enhanced UI 状态
        let appElement = getApplicationElement(for: window)
        var wasEnhancedUI: Bool? = nil

        if let app = appElement {
            wasEnhancedUI = getEnhancedUI(for: app)

            // 4. 如果 Enhanced UI 已启用，则禁用它
            if wasEnhancedUI == true {
                setEnhancedUI(for: app, enabled: false)
            }
        }

        // 5. 两步法设置窗口：Position -> Size
        let _ = setPosition(window, point: adjustedRect.origin)
        let sizeResult = setSize(window, size: adjustedRect.size)

        // 6. 如果 Size 设置失败但窗口标记为可设置，尝试三步法
        if sizeResult != .success && canSetSize {
            let _ = setSize(window, size: adjustedRect.size)
            let _ = setPosition(window, point: adjustedRect.origin)
            let _ = setSize(window, size: adjustedRect.size)
        }

        // 7. 恢复 Enhanced UI
        if wasEnhancedUI == true, let app = appElement {
            setEnhancedUI(for: app, enabled: true)
        }
    }

    private func setPosition(_ window: AXUIElement, point: CGPoint) -> AXError {
        var pt = point
        if let posValue = AXValueCreate(.cgPoint, &pt) {
            return AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)
        }
        return .failure
    }

    private func setSize(_ window: AXUIElement, size: CGSize) -> AXError {
        var sz = size
        if let sizeValue = AXValueCreate(.cgSize, &sz) {
            return AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        }
        return .failure
    }
    
    private func getScreen(containing rect: CGRect) -> NSScreen? {
        guard let primaryScreen = NSScreen.screens.first else { return NSScreen.main }
        let primaryHeight = primaryScreen.frame.height
        let cocoaY = primaryHeight - (rect.origin.y + rect.height)
        let cocoaCenter = CGPoint(x: rect.midX, y: cocoaY + rect.height / 2)
        return NSScreen.screens.first { $0.frame.contains(cocoaCenter) } ?? NSScreen.main
    }

    // MARK: - Enhanced UI Handling (Rectangle's strategy)

    /// 获取窗口所属的应用程序元素
    private func getApplicationElement(for window: AXUIElement) -> AXUIElement? {
        var appRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(window, kAXParentAttribute as CFString, &appRef)

        if result == .success, let app = appRef {
            return (app as! AXUIElement)
        }
        return nil
    }

    /// 获取应用程序的 Enhanced UI 状态
    private func getEnhancedUI(for appElement: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, "AXEnhancedUserInterface" as CFString, &value)

        if result == .success, let boolValue = value as? Bool {
            return boolValue
        }
        return nil
    }

    /// 设置应用程序的 Enhanced UI 状态
    private func setEnhancedUI(for appElement: AXUIElement, enabled: Bool) {
        AXUIElementSetAttributeValue(appElement, "AXEnhancedUserInterface" as CFString, enabled as CFBoolean)
    }
}
