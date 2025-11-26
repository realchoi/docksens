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

// ⚡️ Wrapper to make AXUIElement Sendable
struct SendableAXUIElement: @unchecked Sendable {
    let element: AXUIElement
}

// MARK: - Data Models

struct WindowInfo: Identifiable, @unchecked Sendable {
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
    
    // ⚡️ 缓存的 AXUIElement，用于 O(1) 操作
    let axElement: SendableAXUIElement?
}

struct DockIconInfo: Identifiable, Sendable {
    let id: Int
    let title: String
    let frame: CGRect
    let url: URL?
}

private struct AXWindowData: @unchecked Sendable {
    let pid: pid_t
    let title: String
    let frame: CGRect
    let isMinimized: Bool
    let appName: String
    let bundleID: String
    let axElement: SendableAXUIElement
}

// MARK: - Window Engine Actor

actor WindowEngine {
    
    // MARK: - Image Cache
    
    private let imageCache = WindowImageCache(maxSize: 50, maxAge: 2.5)
    
    // ⚡️ App AX 缓存
    private let appAXCache = AppAXCache()
    
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
                    // ⚡️ 传递缓存
                    return self.fetchAXWindowData(for: app, using: self.appAXCache)
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
                                    let croppedImage = self.cropTransparentEdges(from: fullImage) ?? fullImage
                                    image = croppedImage
                                    // 存入缓存
                                    await self.imageCache.setImage(croppedImage, for: sysID, frame: axWin.frame)
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
                            isMinimized: axWin.isMinimized,
                            axElement: axWin.axElement
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
        async let scWindowsTask = try? SCShareableContent.current.windows
        
        // 1. 仅获取目标应用的 AX 窗口
        // ⚡️ 使用缓存
        let axWindows = self.fetchAXWindowData(for: targetApp, using: self.appAXCache)
        
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
                        let croppedImage = self.cropTransparentEdges(from: fullImage) ?? fullImage
                        image = croppedImage
                        // 存入缓存
                        await self.imageCache.setImage(croppedImage, for: sysID, frame: axWin.frame)
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
                isMinimized: axWin.isMinimized,
                axElement: axWin.axElement
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
    
    // MARK: - Accessibility Fetcher (nonisolated)
    
    nonisolated private func fetchAXWindowData(for app: NSRunningApplication, using cache: AppAXCache) -> [AXWindowData] {
        let pid = app.processIdentifier
        // ⚡️ 使用缓存获取 App AX 对象
        let appRef = cache.getElement(for: pid)
        
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
            
            let data = AXWindowData(
                pid: pid,
                title: title,
                frame: frame,
                isMinimized: isMinimized,
                // 修改点：支持 "Unknown" 的本地化
                appName: app.localizedName ?? String(localized: "Unknown"),
                bundleID: app.bundleIdentifier ?? "",
                axElement: SendableAXUIElement(element: axWindow)
            )
            results.append(data)
        }
        
        return results
    }
    
    // MARK: - Fast State Checking
    
    /// 快速检查应用是否处于前台且有可见的焦点窗口
    /// 用于 Dock 点击时的“最小化”判断
    nonisolated func isAppFocusedAndVisible(pid: pid_t) -> Bool {
        // 1. 检查是否是前台应用
        guard let frontmost = NSWorkspace.shared.frontmostApplication,
              frontmost.processIdentifier == pid else {
            return false
        }
        
        // 2. 获取 AX 对象
        let appRef = appAXCache.getElement(for: pid)
        
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
    
    // MARK: - 2. Dock Scanning
    
    // scanDockIcons 已移除，逻辑已迁移至 DockMonitor


    nonisolated static func checkAccessibilityPermission() -> Bool {
        return AXUtils.checkAccessibilityPermission()
    }
    
    // 裁剪 CGImage 边缘的透明区域
    // ⚡️ 性能优化版：从边缘向内扫描，大幅减少遍历次数
    // ⚡️ 二次优化：使用 Stride Skipping (跳步扫描) 加速初始探测
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
        
        // ⚡️ 优化策略：
        // 1. 粗略扫描：每隔 4 个像素检查一次 (stride = 4)
        // 2. 精细修正：找到非透明点后，回溯查找精确边界
        let stride = 4
        
        // 1. 扫描 Top (minY)
        var foundTop = false
        for y in 0..<height {
            // 快速扫描行
            var rowHasContent = false
            for x in Swift.stride(from: 0, to: width, by: stride) {
                if !isTransparent(x, y) {
                    rowHasContent = true
                    break
                }
            }
            
            if rowHasContent {
                minY = y
                foundTop = true
                break
            }
        }
        
        // 如果没找到顶部非透明像素，说明全是透明的
        if !foundTop { return nil }
        
        // 2. 扫描 Bottom (maxY)
        for y in (minY..<height).reversed() {
            var rowHasContent = false
            for x in Swift.stride(from: 0, to: width, by: stride) {
                if !isTransparent(x, y) {
                    rowHasContent = true
                    break
                }
            }
            
            if rowHasContent {
                maxY = y
                break
            }
        }
        
        // 3. 扫描 Left (minX) - 仅在 minY...maxY 范围内扫描
        for x in 0..<width {
            var colHasContent = false
            // 纵向扫描也可以跳步
            for y in Swift.stride(from: minY, to: maxY + 1, by: stride) {
                if !isTransparent(x, y) {
                    colHasContent = true
                    break
                }
            }
            
            if colHasContent {
                minX = x
                break
            }
        }
        
        // 4. 扫描 Right (maxX) - 仅在 minY...maxY 范围内扫描
        for x in (minX..<width).reversed() {
            var colHasContent = false
            for y in Swift.stride(from: minY, to: maxY + 1, by: stride) {
                if !isTransparent(x, y) {
                    colHasContent = true
                    break
                }
            }
            
            if colHasContent {
                maxX = x
                break
            }
        }
        
        // ⚡️ 精细修正：因为跳步扫描可能漏掉边界上的像素，稍微扩大边界以确保安全
        // 或者进行局部回溯（这里为了性能，简单地向外扩展 stride 大小，反正透明边缘多切一点少切一点影响不大）
        minX = max(0, minX - stride)
        maxX = min(width - 1, maxX + stride)
        minY = max(0, minY - stride)
        maxY = min(height - 1, maxY + stride)
        
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