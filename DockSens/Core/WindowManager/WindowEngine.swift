//
//  WindowEngine.swift
//  DockSens
//
//  Created by DockSens Team.
//

import AppKit
import ApplicationServices
import CoreGraphics
import ScreenCaptureKit

// MARK: - Data Models

/// 窗口信息 (用于 Switcher)
struct WindowInfo: Identifiable, Sendable {
    let id: UInt32
    let pid: pid_t
    let title: String
    let appName: String
    let bundleIdentifier: String
    let frame: CGRect
    let image: CGImage?
}

/// Dock 图标数据模型 (用于 Dock Hover)
struct DockIconInfo: Identifiable, Sendable {
    let id: Int
    let title: String
    let frame: CGRect
    let url: URL?
}

// MARK: - Window Engine Actor

actor WindowEngine {
    
    // MARK: - 1. Window Scanning (Switcher / SCK)
    
    /// 使用 ScreenCaptureKit 扫描，并过滤出有效的可激活窗口
    func activeWindows() async throws -> [WindowInfo] {
        // 1. 获取 SCK 原始内容
        let content = try await SCShareableContent.current
        
        // 2. 获取 NSWorkspace 的运行中 App 列表 (用于验证 PID 和排除 Ghost 窗口)
        let regularApps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .reduce(into: [pid_t: NSRunningApplication]()) { $0[$1.processIdentifier] = $1 }
        
        // 3. 获取当前进程 (DockSens) 的 PID，用于精准排除
        let selfPID = ProcessInfo.processInfo.processIdentifier
        
        // 4. 过滤窗口
        let validWindows = content.windows.filter { window in
            // A. 基础过滤：排除屏幕外、不可见层级、极小窗口
            guard window.isOnScreen,
                  window.windowLayer == 0,
                  window.frame.width > 10, window.frame.height > 10 else { return false }
            
            // B. ❌ 关键修复：绝对排除 DockSens 自身
            // 如果不排除，DockSens 窗口会进入列表，导致 index 1 (第二个窗口) 变成 DockSens 自己，
            // 从而破坏 "Alt-Tab 切换回上一个 App" 的逻辑。
            guard let appPID = window.owningApplication?.processID,
                  appPID != selfPID else {
                return false
            }
            
            // C. Ghost PID 修复：确保该窗口归属于一个“常规 App”
            guard let pid = window.owningApplication?.processID,
                  regularApps[pid] != nil else {
                return false
            }
            
            return true
        }
        
        // 5. 并发截图
        return await withTaskGroup(of: WindowInfo?.self) { group in
            for scWindow in validWindows {
                group.addTask {
                    let filter = SCContentFilter(desktopIndependentWindow: scWindow)
                    let config = SCStreamConfiguration()
                    config.sourceRect = scWindow.frame
                    config.width = Int(scWindow.frame.width)
                    config.height = Int(scWindow.frame.height)
                    config.showsCursor = false
                    
                    // 捕获异常防止单个窗口失败导致整体崩溃
                    let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                    
                    guard let pid = scWindow.owningApplication?.processID else { return nil }
                    
                    return WindowInfo(
                        id: scWindow.windowID,
                        pid: pid,
                        title: scWindow.title ?? "",
                        appName: scWindow.owningApplication?.applicationName ?? "Unknown",
                        bundleIdentifier: scWindow.owningApplication?.bundleIdentifier ?? "",
                        frame: scWindow.frame,
                        image: image
                    )
                }
            }
            
            // 收集结果
            var results: [WindowInfo] = []
            for await result in group {
                if let info = result {
                    results.append(info)
                }
            }
            
            // 6. 恢复原始 Z-Order 排序 (SCK 返回的 windows 数组本身就是按 Z-Order 排序的)
            // 这里先按 Z-Order 排好，后续 WindowManager 会再根据 MRU 调整顺序
            return results.sorted { w1, w2 in
                let idx1 = validWindows.firstIndex(where: { $0.windowID == w1.id }) ?? Int.max
                let idx2 = validWindows.firstIndex(where: { $0.windowID == w2.id }) ?? Int.max
                return idx1 < idx2
            }
        }
    }
    
    // MARK: - 2. Dock Scanning (Hover / AX)
    
    /// 扫描 Dock 栏图标布局
    func scanDockIcons() -> [DockIconInfo] {
        var icons: [DockIconInfo] = []
        
        let dockApps = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == "com.apple.dock" }
        guard let dockApp = dockApps.first else { return [] }
        
        let dockRef = AXUIElementCreateApplication(dockApp.processIdentifier)
        
        guard let children = getAXAttribute(dockRef, kAXChildrenAttribute, ofType: [AXUIElement].self) else { return [] }
        
        for child in children {
            let role = getAXAttribute(child, kAXRoleAttribute, ofType: String.self)
            if role == "AXList" {
                guard let iconElements = getAXAttribute(child, kAXChildrenAttribute, ofType: [AXUIElement].self) else { continue }
                
                for iconRef in iconElements {
                    if let info = extractDockIconInfo(iconRef) {
                        icons.append(info)
                    }
                }
            }
        }
        return icons
    }

    private func extractDockIconInfo(_ element: AXUIElement) -> DockIconInfo? {
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

        return DockIconInfo(
            id: Int(frame.origin.x),
            title: title,
            frame: frame,
            url: url
        )
    }
    
    // MARK: - Helpers
    
    private func getAXAttribute<T>(_ element: AXUIElement, _ attribute: String, ofType type: T.Type) -> T? {
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
    
    // MARK: - Static Permissions
    
    nonisolated static func checkAccessibilityPermission() -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}