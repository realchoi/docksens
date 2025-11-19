//
//  WindowEngine.swift
//  DockSens
//
//  Created by DockSens Team.
//

import AppKit
import ApplicationServices
import CoreGraphics

// MARK: - Data Models

/// 跨 Actor 传输的窗口数据模型
/// 必须遵循 Sendable 协议，确保在并发环境中传递是安全的 (值语义)。
struct WindowInfo: Identifiable, Sendable {
    let id: Int // 简单的 Hash ID，用于 SwiftUI 循环
    let pid: pid_t
    let title: String
    let appName: String
    let bundleIdentifier: String
    let frame: CGRect
    let isMinimized: Bool
}

/// Dock 图标数据模型
struct DockIconInfo: Identifiable, Sendable {
    let id: Int
    let title: String
    let frame: CGRect
    // 用于后续匹配 App 窗口
    let url: URL? 
}

// MARK: - Window Engine Actor

/// 窗口引擎 Actor
/// 使用 actor 隔离状态，防止多线程同时访问底层的 AXUIElement API 导致崩溃或数据竞争。
actor WindowEngine {
    
    // MARK: - Window Scanning
    
    /// 扫描当前系统所有活跃窗口
    /// - Returns: 包含窗口信息的数组
    func activeWindows() throws -> [WindowInfo] {
        var windows: [WindowInfo] = []
        
        // 1. 获取所有运行中的常规应用程序
        // NSWorkspace.runningApplications 是线程安全的
        let apps = NSWorkspace.shared.runningApplications.filter { app in
            return app.activationPolicy == .regular
        }
        
        for app in apps {
            // 2. 创建 Accessibility 应用引用 (AXUIElement)
            let appRef = AXUIElementCreateApplication(app.processIdentifier)
            
            // 3. 获取该应用下的所有窗口引用列表 (kAXWindowsAttribute)
            // FIX: 显式传入 [AXUIElement].self 以解决泛型推断错误
            guard let windowList = getAXAttribute(appRef, kAXWindowsAttribute, ofType: [AXUIElement].self) else {
                continue
            }
            
            for windowRef in windowList {
                // 4. 提取单个窗口的详细属性
                if let info = extractWindowInfo(windowRef, app: app) {
                    windows.append(info)
                }
            }
        }
        
        return windows
    }
    
    /// 提取单个窗口的信息
    private func extractWindowInfo(_ element: AXUIElement, app: NSRunningApplication) -> WindowInfo? {
        // FIX: 显式传入 String.self
        let title = getAXAttribute(element, kAXTitleAttribute, ofType: String.self) ?? ""
        let subrole = getAXAttribute(element, kAXSubroleAttribute, ofType: String.self) ?? ""
        
        // 过滤规则：忽略 AXUnknown 类型的窗口
        if subrole == "AXUnknown" { return nil }
        
        // 获取位置和大小
        // AX API 返回的是 AXValue (Core Foundation 类型)，需要显式指定类型进行解包
        var frame = CGRect.zero
        
        // FIX: 显式传入 AXValue.self
        if let posValue = getAXAttribute(element, kAXPositionAttribute, ofType: AXValue.self),
           let sizeValue = getAXAttribute(element, kAXSizeAttribute, ofType: AXValue.self) {
            
            var pos = CGPoint.zero
            var size = CGSize.zero
            AXValueGetValue(posValue, .cgPoint, &pos)
            AXValueGetValue(sizeValue, .cgSize, &size)
            frame = CGRect(origin: pos, size: size)
        }
        
        // 检查是否最小化
        // FIX: 显式传入 Bool.self
        let isMinimized = getAXAttribute(element, kAXMinimizedAttribute, ofType: Bool.self) ?? false
        
        // 过滤规则：忽略极其微小的窗口（通常是不可见的定位点或后台窗口）
        if frame.width < 10 || frame.height < 10 { return nil }

        // 生成唯一的 ID
        // 简单的异或哈希，用于 SwiftUI 的 Identifiable
        let uniqueID = Int(frame.origin.x) ^ Int(frame.origin.y) ^ Int(app.processIdentifier)

        return WindowInfo(
            id: uniqueID,
            pid: app.processIdentifier,
            title: title,
            appName: app.localizedName ?? "Unknown",
            bundleIdentifier: app.bundleIdentifier ?? "",
            frame: frame,
            isMinimized: isMinimized
        )
    }
    
    // MARK: - Dock Scanning

    /// 扫描 Dock 栏图标布局
    /// 注意：这是一个相对耗时的操作，建议仅在显示器分辨率改变或 Dock 启动时调用缓存
    func scanDockIcons() -> [DockIconInfo] {
        var icons: [DockIconInfo] = []
        
        // 1. 获取 Dock 进程
        let dockApps = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == "com.apple.dock" }
        guard let dockApp = dockApps.first else { return [] }
        
        let dockRef = AXUIElementCreateApplication(dockApp.processIdentifier)
        
        // 2. 遍历 Dock 的子元素找到 "List" (存放图标的容器)
        guard let children = getAXAttribute(dockRef, kAXChildrenAttribute, ofType: [AXUIElement].self) else { return [] }
        
        for child in children {
            let role = getAXAttribute(child, kAXRoleAttribute, ofType: String.self)
            // Dock 的图标列表通常是一个 AXList
            if role == "AXList" {
                guard let iconElements = getAXAttribute(child, kAXChildrenAttribute, ofType: [AXUIElement].self) else { continue }
                
                // 3. 遍历图标
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
        
        // 过滤掉非 DockItem (如分隔符)
        if role != "AXDockItem" { return nil }
        
        var frame = CGRect.zero
        if let posValue = getAXAttribute(element, kAXPositionAttribute, ofType: AXValue.self),
           let sizeValue = getAXAttribute(element, kAXSizeAttribute, ofType: AXValue.self) {
            var pos = CGPoint.zero
            var size = CGSize.zero
            AXValueGetValue(posValue, .cgPoint, &pos)
            AXValueGetValue(sizeValue, .cgSize, &size)
            
            // 转换坐标系：Cocoa (左下角原点) vs Quartz (左上角原点)
            // AXAPI 返回的是屏幕坐标 (Top-Left)，适合直接用于 Window Frame 计算
            frame = CGRect(origin: pos, size: size)
        }
        
        // 获取 URL (如果支持)
        var url: URL? = nil
        if let urlString = getAXAttribute(element, kAXURLAttribute, ofType: String.self) {
            url = URL(string: urlString)
        } else if let urlRef = getAXAttribute(element, kAXURLAttribute, ofType: URL.self) {
            // 有些系统版本直接返回 URL
            url = urlRef
        }

        return DockIconInfo(
            id: Int(frame.origin.x),
            title: title,
            frame: frame,
            url: url
        )
    }
    
    // MARK: - AXUIElement Helpers
    
    /// 泛型辅助方法：安全地获取 AX 属性
    ///
    /// - Parameters:
    ///   - element: 目标 AXUIElement
    ///   - attribute: 属性名称 (如 kAXTitleAttribute)
    ///   - type: **新增参数**，显式传入期望的类型 (如 String.self)，解决编译器泛型推断失败的问题
    /// - Returns: 转换后的属性值，失败则返回 nil
    private func getAXAttribute<T>(_ element: AXUIElement, _ attribute: String, ofType type: T.Type) -> T? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        
        if result == .success, let value = value {
            // 尝试将 CFTypeRef 转换为泛型 T
            return value as? T
        }
        return nil
    }
    
    // MARK: - Static Permissions
    
    /// 检查并请求辅助功能权限
    /// 标记为 nonisolated，因为 AXIsProcessTrusted 是线程安全的，可以直接在主线程调用
    nonisolated static func checkAccessibilityPermission() -> Bool {
        // kAXTrustedCheckOptionPrompt: true 表示如果没有权限，系统会自动弹出提示框
        // FIX: 添加 .takeUnretainedValue() 以处理 Unmanaged<CFString>
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}