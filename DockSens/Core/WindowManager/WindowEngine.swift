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

// Private API to get CGWindowID from AXUIElement
// Moved to AppAXCache.swift

// ⚡️ Wrapper to make AXUIElement Sendable
// Moved to AppAXCache.swift

// MARK: - Data Models

// MARK: - Data Models

// WindowInfo and DockIconInfo moved to WindowInfo.swift

private struct AXWindowData: @unchecked Sendable {
    let pid: pid_t
    let title: String
    let frame: CGRect
    let isMinimized: Bool
    let appName: String
    let bundleID: String
    // Store as AnyObject to avoid MainActor inference
    let axElement: AnyObject
    // ⚡️ 新增：直接获取的 WindowID
    let windowID: UInt32
}

// MARK: - Window Engine Actor

actor WindowEngine {
    
    // ... (omitted properties)
    
    // ⚡️ App AX 缓存
    private let appAXCache = SafeAppAXCache()
    
    // ... (omitted activeWindows and windows(for:) implementations - assume they are updated to use AnyObject in WindowInfo constructor)
    
    // MARK: - Accessibility Fetcher (nonisolated)
    
    nonisolated private func fetchAXWindowData(for app: NSRunningApplication, using cache: SafeAppAXCache) async -> [AXWindowData] {
        let pid = app.processIdentifier
        // ⚡️ 使用缓存获取 App AX 对象 (await and cast)
        let appRefStorage = await cache.getElement(for: pid)
        let appRef = appRefStorage as! AXUIElement
        
        guard let windowsRef = AXUtils.getAXAttribute(appRef, kAXWindowsAttribute, ofType: [AXUIElement].self) else {
            return []
        }
        
        var results: [AXWindowData] = []
        
        for axWindow in windowsRef {
            let title = AXUtils.getAXAttribute(axWindow, kAXTitleAttribute, ofType: String.self) ?? ""
            if title.isEmpty { continue }
            
            var frame: CGRect = .zero
            if let posValue = AXUtils.getAXAttribute(axWindow, kAXPositionAttribute, ofType: AXValue.self),
               let sizeValue = AXUtils.getAXAttribute(axWindow, kAXSizeAttribute, ofType: AXValue.self) {
                var pos = CGPoint.zero
                var size = CGSize.zero
                AXValueGetValue(posValue, .cgPoint, &pos)
                AXValueGetValue(sizeValue, .cgSize, &size)
                frame = CGRect(origin: pos, size: size)
            }
            
            if frame.width < 20 || frame.height < 20 { continue }
            
            let isMinimized = AXUtils.getAXAttribute(axWindow, kAXMinimizedAttribute, ofType: Bool.self) ?? false
            
            // ⚡️ 尝试获取 WindowID
            var windowID: UInt32 = 0
            // Cast axWindow to AnyObject for _AXUIElementGetWindow
            _ = _AXUIElementGetWindow(axWindow as AnyObject, &windowID)
            
            let data = AXWindowData(
                pid: pid,
                title: title,
                frame: frame,
                isMinimized: isMinimized,
                // 修改点：支持 "Unknown" 的本地化
                appName: app.localizedName ?? String(localized: "Unknown"),
                bundleID: app.bundleIdentifier ?? "",
                // Store as AnyObject
                axElement: axWindow as AnyObject,
                windowID: windowID
            )
            results.append(data)
        }
        
        return results
    }
    
    // MARK: - Fast State Checking
    
    /// 快速检查应用是否处于前台且有可见的焦点窗口
    /// 用于 Dock 点击时的“最小化”判断
    nonisolated func isAppFocusedAndVisible(pid: pid_t) async -> Bool {
        // 1. 检查是否是前台应用
        guard let frontmost = await MainActor.run(body: { NSWorkspace.shared.frontmostApplication }),
              frontmost.processIdentifier == pid else {
            return false
        }
        
        // 2. 获取 AX 对象 (await cache)
        // Since we are nonisolated, we can await the actor
        // But we need access to appAXCache.
        // appAXCache is private to WindowEngine.
        // We cannot access it from nonisolated method unless we pass it or expose it.
        // But WindowEngine is an actor.
        // I should make this method isolated to the actor (remove nonisolated) or pass the cache?
        // If I make it isolated, I can access appAXCache.
        // Let's make it isolated (remove nonisolated).
        
        return await self.checkAppFocusedAndVisible(pid: pid)
    }
    
    private func checkAppFocusedAndVisible(pid: pid_t) async -> Bool {
         // 2. 获取 AX 对象
        let appRefStorage = await appAXCache.getElement(for: pid)
        let appRef = appRefStorage as! AXUIElement
        
        // 3. 获取焦点窗口
        var focusedWindowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &focusedWindowRef) == .success else {
            return false
        }
        let focusedWindow = focusedWindowRef as! AXUIElement
        
        // 4. 检查最小化状态
        // 如果窗口被最小化，它通常不会是 FocusedWindow，或者 Minimized 属性为 true
        if let isMinimized = AXUtils.getAXAttribute(focusedWindow, kAXMinimizedAttribute, ofType: Bool.self),
           isMinimized {
            return false
        }
        
        // 5. 再次确认该窗口是否有效（有标题或大小）
        // 有些应用可能有不可见的焦点窗口
        if let sizeValue = AXUtils.getAXAttribute(focusedWindow, kAXSizeAttribute, ofType: AXValue.self) {
            var size = CGSize.zero
            AXValueGetValue(sizeValue, .cgSize, &size)
            if size.width < 10 || size.height < 10 { return false }
        }
        
        return true
    }
    
    // MARK: - Image Cache
    
    private let imageCache = WindowImageCache(maxSize: 50, maxAge: 2.5)
    
    // ⚡️ App AX 缓存 (Declared at top)
    // private let appAXCache = SafeAppAXCache()
    
    // MARK: - SCShareableContent Micro-caching
    
    private var cachedShareableContent: SCShareableContent?
    private var lastContentFetchTime: Date?
    private let contentCacheDuration: TimeInterval = 0.2 // 200ms cache
    
    private func getShareableContent() async throws -> SCShareableContent {
        if let content = cachedShareableContent,
           let lastFetch = lastContentFetchTime,
           Date().timeIntervalSince(lastFetch) < contentCacheDuration {
            return content
        }
        
        let content = try await SCShareableContent.current
        cachedShareableContent = content
        lastContentFetchTime = Date()
        return content
    }
    
    // MARK: - 1. Window Scanning (AX-Driven with SCK-Enrichment)
    
    func activeWindows() async throws -> [WindowInfo] {
        async let scWindowsTask = try? self.getShareableContent().windows
        
        let regularApps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
        
        let selfPID = ProcessInfo.processInfo.processIdentifier
        
        // 1. 获取 AX 语义窗口
        let axWindows = await withTaskGroup(of: [AXWindowData].self) { group in
            for app in regularApps {
                if app.processIdentifier == selfPID { continue }
                group.addTask {
                    // ⚡️ 传递缓存 (async call)
                    return await self.fetchAXWindowData(for: app, using: self.appAXCache)
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
                            isMinimized: false,
                            axElement: nil
                        )
                        return [dummyInfo]
                    }
                    
                    var appResults: [WindowInfo] = []
                    
                    // ⚡️ Fix: Filter SC windows for this app and consume them to prevent duplicates
                    let appSCWindows = scWindows.filter { $0.owningApplication?.processID == app.processIdentifier }
                    
                    // Use multi-pass matching
                    let matchedPairs = self.matchWindows(appWindows, with: appSCWindows)
                    
                    for (axWin, match) in matchedPairs {
                        var image: CGImage? = nil
                        var sysID: UInt32 = axWin.windowID // 默认为 AX 获取到的 ID
                        
                        if let scMatch = match {
                            sysID = scMatch.windowID
                            
                            // ⚡️ 性能优化：先检查缓存
                            if let cachedImage = await self.imageCache.getImage(for: sysID, frame: axWin.frame) {
                                image = cachedImage
                            } else {
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
                                    let croppedImage = ImageUtils.cropTransparentEdges(from: fullImage) ?? fullImage
                                    image = croppedImage
                                    // 存入缓存
                                    await self.imageCache.setImage(croppedImage, for: sysID, frame: axWin.frame)
                                }
                            }
                        }
                        
                        appResults.append(await WindowInfo(
                            id: UUID(),
                            windowID: sysID,
                            pid: axWin.pid,
                            title: axWin.title,
                            appName: axWin.appName,
                            bundleIdentifier: axWin.bundleID,
                            frame: axWin.frame,
                            image: image,
                            isMinimized: axWin.isMinimized,
                            axElement: AXElementWrapper(axWin.axElement)
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
            let sorted = finalResults.sorted {
                if $0.windowID != $1.windowID { return $0.windowID > $1.windowID }
                return $0.pid < $1.pid
            }
            
            // 📊 输出缓存统计信息（仅在开发模式，且每 5 次请求输出一次）
            #if DEBUG
            let stats = await imageCache.getStats()
            if stats.totalRequests % 5 == 0 {
                print("📊 WindowEngine Cache: Hit Rate=\(String(format: "%.1f%%", stats.hitRate * 100)), Size=\(stats.cacheSize), Requests=\(stats.totalRequests)")
            }
            #endif
            
            return sorted
        }
    }
    
    // ⚡️ 性能优化：仅获取特定应用的窗口
    func windows(for targetApp: NSRunningApplication) async throws -> [WindowInfo] {
        async let scWindowsTask = try? self.getShareableContent().windows
        
        // 1. 仅获取目标应用的 AX 窗口
        // ⚡️ 使用缓存 (async call)
        let axWindows = await self.fetchAXWindowData(for: targetApp, using: self.appAXCache)
        
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
                isMinimized: false,
                axElement: nil
            )
            return [dummyInfo]
        }
        
        var appResults: [WindowInfo] = []
        
        // ⚡️ Fix: Filter SC windows for this app and consume them to prevent duplicates
        let appSCWindows = scWindows.filter { $0.owningApplication?.processID == targetApp.processIdentifier }
        
        // Use multi-pass matching
        let matchedPairs = self.matchWindows(axWindows, with: appSCWindows)
        
        for (axWin, match) in matchedPairs {
            var image: CGImage? = nil
            var sysID: UInt32 = axWin.windowID
            
            if let scMatch = match {
                sysID = scMatch.windowID
                
                // ⚡️ 性能优化：先检查缓存
                if let cachedImage = await self.imageCache.getImage(for: sysID, frame: axWin.frame) {
                    image = cachedImage
                } else {
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
                        let croppedImage = ImageUtils.cropTransparentEdges(from: fullImage) ?? fullImage
                        image = croppedImage
                        // 存入缓存
                        await self.imageCache.setImage(croppedImage, for: sysID, frame: axWin.frame)
                    }
                }
            }
            
            appResults.append(await WindowInfo(
                id: UUID(),
                windowID: sysID,
                pid: axWin.pid,
                title: axWin.title,
                appName: axWin.appName,
                bundleIdentifier: axWin.bundleID,
                frame: axWin.frame,
                image: image,
                isMinimized: axWin.isMinimized,
                axElement: AXElementWrapper(axWin.axElement)
            ))
        }
        
        let sorted = appResults.sorted {
            if $0.windowID != $1.windowID { return $0.windowID > $1.windowID }
            return $0.pid < $1.pid
        }
        
        // 📊 输出缓存统计信息（仅在开发模式，且每 5 次请求输出一次）
        #if DEBUG
        let stats = await imageCache.getStats()
        if stats.totalRequests % 5 == 0 {
            print("📊 WindowEngine Cache: Hit Rate=\(String(format: "%.1f%%", stats.hitRate * 100)), Size=\(stats.cacheSize), Requests=\(stats.totalRequests)")
        }
        #endif
        
        return sorted
    }
    
    // MARK: - 2. Dock Scanning
    
    // scanDockIcons 已移除，逻辑已迁移至 DockMonitor


    nonisolated static func checkAccessibilityPermission() -> Bool {
        return AXUtils.checkAccessibilityPermission()
    }
    

    
    // MARK: - Helper Methods
    
    private nonisolated func matchWindows(_ axWindows: [AXWindowData], with scWindows: [SCWindow]) -> [(AXWindowData, SCWindow?)] {
        var matches: [Int: SCWindow] = [:] // axWindow index -> SCWindow
        var availableSC = scWindows
        
        // Pass 1: Exact ID Match (Highest Confidence)
        for (index, axWin) in axWindows.enumerated() {
            if axWin.windowID == 0 { continue }
            if let scIndex = availableSC.firstIndex(where: { $0.windowID == axWin.windowID }) {
                matches[index] = availableSC[scIndex]
                availableSC.remove(at: scIndex)
            }
        }
        
        // Pass 2: Strong Match (Title + Geometry)
        for (index, axWin) in axWindows.enumerated() {
            if matches[index] != nil { continue }
            
            if let scIndex = availableSC.firstIndex(where: { scWin in
                if scWin.windowLayer != 0 { return false }
                
                // Title Match
                let scTitle = scWin.title ?? ""
                let titleMatch = !axWin.title.isEmpty && !scTitle.isEmpty &&
                    (scTitle.contains(axWin.title) || axWin.title.contains(scTitle))
                
                if !titleMatch { return false }
                
                // Geometry Match
                let axCenter = CGPoint(x: axWin.frame.midX, y: axWin.frame.midY)
                let scCenter = CGPoint(x: scWin.frame.midX, y: scWin.frame.midY)
                let distance = hypot(axCenter.x - scCenter.x, axCenter.y - scCenter.y)
                
                // Strict distance for strong match
                return distance < 50
            }) {
                matches[index] = availableSC[scIndex]
                availableSC.remove(at: scIndex)
            }
        }
        
        // Pass 3: Weak Match (Best Geometry)
        for (index, axWin) in axWindows.enumerated() {
            if matches[index] != nil { continue }
            
            var bestIndex: Int?
            var minScore: Double = Double.infinity
            
            for (scIndex, scWin) in availableSC.enumerated() {
                if scWin.windowLayer != 0 { continue }
                
                let axCenter = CGPoint(x: axWin.frame.midX, y: axWin.frame.midY)
                let scCenter = CGPoint(x: scWin.frame.midX, y: scWin.frame.midY)
                let distance = hypot(axCenter.x - scCenter.x, axCenter.y - scCenter.y)
                
                if distance < 100 {
                    let axArea = axWin.frame.width * axWin.frame.height
                    let scArea = scWin.frame.width * scWin.frame.height
                    if scArea > 0 && axArea > 0 {
                        let ratio = scArea / axArea
                        if ratio > 0.5 && ratio < 2.0 {
                            // Score based on distance (lower is better)
                            if distance < minScore {
                                minScore = distance
                                bestIndex = scIndex
                            }
                        }
                    }
                }
            }
            
            if let best = bestIndex {
                matches[index] = availableSC[best]
                availableSC.remove(at: best)
            }
        }
        
        // Construct result
        return axWindows.enumerated().map { (index, axWin) in
            (axWin, matches[index])
        }
    }
}