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
                            // 配置截图参数 - 不捕获阴影
                            let filter = SCContentFilter(desktopIndependentWindow: scMatch)
                            let config = SCStreamConfiguration()
                            config.showsCursor = false
                            config.ignoreShadowsSingleWindow = true  // 不捕获窗口阴影
                            config.width = Int(scMatch.frame.width * 2)
                            config.height = Int(scMatch.frame.height * 2)
                            
                            // 捕获并裁剪透明边缘
                            if let fullImage = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) {
                                // 裁剪掉图片边缘的透明区域
                                image = self.cropTransparentEdges(from: fullImage) ?? fullImage
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
    
    // ⚡️ 性能优化：仅获取特定应用的窗口
    func windows(for targetApp: NSRunningApplication) async throws -> [WindowInfo] {
        async let scWindowsTask = try? SCShareableContent.current.windows
        
        // 1. 仅获取目标应用的 AX 窗口
        let axWindows = self.fetchAXWindowData(for: targetApp)
        
        let scWindows = await scWindowsTask ?? []
        
        // 2. 匹配合并 (仅针对目标应用)
        // 如果该应用没有窗口，创建一个代表应用的“虚拟窗口”
        if axWindows.isEmpty {
            let dummyInfo = WindowInfo(
                id: UUID(),
                windowID: 0,
                pid: targetApp.processIdentifier,
                title: targetApp.localizedName ?? "App",
                appName: targetApp.localizedName ?? "App",
                bundleIdentifier: targetApp.bundleIdentifier ?? "",
                frame: CGRect(x: 0, y: 0, width: 100, height: 100),
                image: nil,
                isMinimized: false
            )
            return [dummyInfo]
        }
        
        var appResults: [WindowInfo] = []
        
        for axWin in axWindows {
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
                // 配置截图参数 - 不捕获阴影
                let filter = SCContentFilter(desktopIndependentWindow: scMatch)
                let config = SCStreamConfiguration()
                config.showsCursor = false
                config.ignoreShadowsSingleWindow = true  // 不捕获窗口阴影
                config.width = Int(scMatch.frame.width * 2)
                config.height = Int(scMatch.frame.height * 2)
                
                // 捕获并裁剪透明边缘
                if let fullImage = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) {
                    // 裁剪掉图片边缘的透明区域
                    image = self.cropTransparentEdges(from: fullImage) ?? fullImage
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
        
        return appResults.sorted {
            if $0.windowID != $1.windowID { return $0.windowID > $1.windowID }
            return $0.pid < $1.pid
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
    
    // 裁剪 CGImage 边缘的透明区域
    // ⚡️ 性能优化版：从边缘向内扫描，大幅减少遍历次数
    nonisolated private func cropTransparentEdges(from image: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height
        
        guard let dataProvider = image.dataProvider,
              let data = dataProvider.data,
              let bytes = CFDataGetBytePtr(data) else {
            return nil
        }
        
        let bytesPerPixel = 4
        let bytesPerRow = image.bytesPerRow
        
        // 检查像素是否透明（alpha < 10）
        // 内联函数以减少调用开销
        func isTransparent(_ x: Int, _ y: Int) -> Bool {
            let offset = y * bytesPerRow + x * bytesPerPixel + 3 // alpha通道
            return bytes[offset] < 10
        }
        
        var minX = 0
        var maxX = width - 1
        var minY = 0
        var maxY = height - 1
        
        // 1. 扫描 Top (minY)
        var foundTop = false
        for y in 0..<height {
            for x in 0..<width {
                if !isTransparent(x, y) {
                    minY = y
                    foundTop = true
                    break
                }
            }
            if foundTop { break }
        }
        
        // 如果没找到顶部非透明像素，说明全是透明的
        if !foundTop { return nil }
        
        // 2. 扫描 Bottom (maxY)
        for y in (minY..<height).reversed() {
            var foundRow = false
            for x in 0..<width {
                if !isTransparent(x, y) {
                    maxY = y
                    foundRow = true
                    break
                }
            }
            if foundRow { break }
        }
        
        // 3. 扫描 Left (minX) - 仅在 minY...maxY 范围内扫描
        var foundLeft = false
        for x in 0..<width {
            for y in minY...maxY {
                if !isTransparent(x, y) {
                    minX = x
                    foundLeft = true
                    break
                }
            }
            if foundLeft { break }
        }
        
        // 4. 扫描 Right (maxX) - 仅在 minY...maxY 范围内扫描
        for x in (minX..<width).reversed() {
            var foundCol = false
            for y in minY...maxY {
                if !isTransparent(x, y) {
                    maxX = x
                    foundCol = true
                    break
                }
            }
            if foundCol { break }
        }
        
        // 校验有效性
        guard minX <= maxX && minY <= maxY else { return nil }
        
        // 裁剪到内容区域
        let cropRect = CGRect(
            x: minX,
            y: minY,
            width: maxX - minX + 1,
            height: maxY - minY + 1
        )
        
        return image.cropping(to: cropRect)
    }
}