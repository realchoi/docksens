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

struct WindowInfo: Identifiable, Sendable {
    // ⚡️ UI 唯一标识 (每次生成，解决渲染冲突)
    let id: UUID
    // ⚡️ 系统标识 (可能为 0，用于排序参考)
    let windowID: UInt32
    
    let pid: pid_t
    let title: String
    let appName: String
    let bundleIdentifier: String
    let frame: CGRect
    let image: CGImage?
    let isMinimized: Bool
}

struct DockIconInfo: Identifiable, Sendable {
    let id: Int
    let title: String
    let frame: CGRect
    let url: URL?
}

private struct AXWindowData: Sendable {
    let pid: pid_t
    let title: String
    let frame: CGRect
    let isMinimized: Bool
    let appName: String
    let bundleID: String
}

// MARK: - Window Engine Actor

actor WindowEngine {
    
    // MARK: - 1. Window Scanning (AX-Driven with SCK-Enrichment)
    
    func activeWindows() async throws -> [WindowInfo] {
        async let scWindowsTask = try? SCShareableContent.current.windows
        
        let regularApps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
        
        let selfPID = ProcessInfo.processInfo.processIdentifier
        
        // 1. 获取 AX 语义窗口
        let axWindows = await withTaskGroup(of: [AXWindowData].self) { group in
            for app in regularApps {
                if app.processIdentifier == selfPID { continue }
                group.addTask {
                    return self.fetchAXWindowData(for: app)
                }
            }
            var allAX: [AXWindowData] = []
            for await list in group {
                allAX.append(contentsOf: list)
            }
            return allAX
        }
        
        let scWindows = await scWindowsTask ?? []
        
        // 2. 匹配合并
        return await withTaskGroup(of: [WindowInfo].self) { group in
            // 遍历所有应用，不仅仅是找到窗口的应用
            for app in regularApps {
                if app.processIdentifier == selfPID { continue }
                
                group.addTask {
                    let appWindows = axWindows.filter { $0.pid == app.processIdentifier }
                    
                    // 如果该应用没有窗口，创建一个代表应用的“虚拟窗口”
                    if appWindows.isEmpty {
                        let dummyInfo = WindowInfo(
                            id: UUID(),
                            windowID: 0,
                            pid: app.processIdentifier,
                            title: app.localizedName ?? "App",
                            appName: app.localizedName ?? "App",
                            bundleIdentifier: app.bundleIdentifier ?? "",
                            frame: CGRect(x: 0, y: 0, width: 100, height: 100), // 默认正方形
                            image: nil,
                            isMinimized: false
                        )
                        return [dummyInfo]
                    }
                    
                    var appResults: [WindowInfo] = []
                    
                    for axWin in appWindows {
                        // 尝试匹配 SCK 窗口
                        let match = scWindows.first { scWin in
                            guard let scPID = scWin.owningApplication?.processID, scPID == axWin.pid else { return false }
                            if scWin.windowLayer != 0 { return false }
                            
                            // 1. 标题匹配
                            let scTitle = scWin.title ?? ""
                            if !axWin.title.isEmpty && !scTitle.isEmpty {
                                if scTitle.contains(axWin.title) || axWin.title.contains(scTitle) {
                                    return true
                                }
                            }
                            
                            // 2. 几何匹配
                            let axCenter = CGPoint(x: axWin.frame.midX, y: axWin.frame.midY)
                            let scCenter = CGPoint(x: scWin.frame.midX, y: scWin.frame.midY)
                            let distance = hypot(axCenter.x - scCenter.x, axCenter.y - scCenter.y)
                            
                            if distance < 100 {
                                let axArea = axWin.frame.width * axWin.frame.height
                                let scArea = scWin.frame.width * scWin.frame.height
                                if scArea > 0 && axArea > 0 {
                                    let ratio = scArea / axArea
                                    if ratio > 0.5 && ratio < 5.0 { return true }
                                }
                            }
                            return false
                        }
                        
                        var image: CGImage? = nil
                        var sysID: UInt32 = 0
                        
                        if let scMatch = match {
                            sysID = scMatch.windowID
                            // 即使最小化也尝试截图 (SCK 可能能截取到，或者截取到图标)
                            let filter = SCContentFilter(desktopIndependentWindow: scMatch)
                            let config = SCStreamConfiguration()
                            config.showsCursor = false
                            config.width = Int(scMatch.frame.width * 2)
                            config.height = Int(scMatch.frame.height * 2)
                            
                            if let fullImage = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) {
                                let axFrame = axWin.frame
                                let scFrame = scMatch.frame
                                
                                if scFrame.width > 0, scFrame.height > 0 {
                                    let scaleX = CGFloat(fullImage.width) / scFrame.width
                                    let scaleY = CGFloat(fullImage.height) / scFrame.height
                                    
                                    let x = max(0, (axFrame.minX - scFrame.minX) * scaleX)
                                    let topOffset = max(0, (axFrame.minY - scFrame.minY) * scaleY)
                                    let w = min(CGFloat(fullImage.width) - x, axFrame.width * scaleX)
                                    let h = min(CGFloat(fullImage.height) - topOffset, axFrame.height * scaleY)
                                    let y = CGFloat(fullImage.height) - topOffset - h
                                    
                                    if w > 0 && h > 0 {
                                        let cropRect = CGRect(x: x, y: y, width: w, height: h)
                                        if let cropped = fullImage.cropping(to: cropRect) {
                                            image = cropped
                                        } else {
                                            image = fullImage
                                        }
                                    } else {
                                        image = fullImage
                                    }
                                } else {
                                    image = fullImage
                                }
                            }
                        }
                        
                        appResults.append(WindowInfo(
                            id: UUID(),
                            windowID: sysID,
                            pid: axWin.pid,
                            title: axWin.title,
                            appName: axWin.appName,
                            bundleIdentifier: axWin.bundleID,
                            frame: axWin.frame,
                            image: image,
                            isMinimized: axWin.isMinimized
                        ))
                    }
                    return appResults
                }
            }
            
            var finalResults: [WindowInfo] = []
            for await infos in group {
                finalResults.append(contentsOf: infos)
            }
            
            // 排序：优先按 SystemID 倒序，没有 ID 的按 PID
            return finalResults.sorted {
                if $0.windowID != $1.windowID { return $0.windowID > $1.windowID }
                return $0.pid < $1.pid
            }
        }
    }
    
    // MARK: - Accessibility Fetcher (nonisolated)
    
    nonisolated private func fetchAXWindowData(for app: NSRunningApplication) -> [AXWindowData] {
        let pid = app.processIdentifier
        let appRef = AXUIElementCreateApplication(pid)
        
        guard let windowsRef = getAXAttribute(appRef, kAXWindowsAttribute, ofType: [AXUIElement].self) else {
            return []
        }
        
        var results: [AXWindowData] = []
        
        for axWindow in windowsRef {
            let title = getAXAttribute(axWindow, kAXTitleAttribute, ofType: String.self) ?? ""
            if title.isEmpty { continue }
            
            var frame: CGRect = .zero
            if let posValue = getAXAttribute(axWindow, kAXPositionAttribute, ofType: AXValue.self),
               let sizeValue = getAXAttribute(axWindow, kAXSizeAttribute, ofType: AXValue.self) {
                var pos = CGPoint.zero
                var size = CGSize.zero
                AXValueGetValue(posValue, .cgPoint, &pos)
                AXValueGetValue(sizeValue, .cgSize, &size)
                frame = CGRect(origin: pos, size: size)
            }
            
            if frame.width < 20 || frame.height < 20 { continue }
            
            let isMinimized = getAXAttribute(axWindow, kAXMinimizedAttribute, ofType: Bool.self) ?? false
            
            let data = AXWindowData(
                pid: pid,
                title: title,
                frame: frame,
                isMinimized: isMinimized,
                // 修改点：支持 "Unknown" 的本地化
                appName: app.localizedName ?? String(localized: "Unknown"),
                bundleID: app.bundleIdentifier ?? ""
            )
            results.append(data)
        }
        
        return results
    }
    
    // MARK: - 2. Dock Scanning (保持不变)
    
    func scanDockIcons() -> [DockIconInfo] {
        // ... (Dock Scanning 代码与之前相同，为了节省篇幅省略，请保留原有的 scanDockIcons 实现) ...
        // 这里的代码没有变动，请直接使用之前的实现
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
                    if let info = extractDockIconInfo(iconRef) { icons.append(info) }
                }
            }
        }
        return icons
    }

    nonisolated private func extractDockIconInfo(_ element: AXUIElement) -> DockIconInfo? {
        // ... (保持不变) ...
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
    
    nonisolated private func getAXAttribute<T>(_ element: AXUIElement, _ attribute: String, ofType type: T.Type) -> T? {
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
    
    nonisolated static func checkAccessibilityPermission() -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}