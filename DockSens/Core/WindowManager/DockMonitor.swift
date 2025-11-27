//
//  DockMonitor.swift
//  DockSens
//
//  Created by DockSens Team.
//

import AppKit
import ApplicationServices
import Combine

/// 负责监听 Dock 的布局变化并维护最新的图标列表
@MainActor
class DockMonitor: ObservableObject {
    
    // MARK: - Published State
    
    /// 当前 Dock 中的图标列表
    @Published private(set) var icons: [DockIconInfo] = []
    
    // MARK: - Private Properties
    
    private var dockApp: NSRunningApplication?
    private var scanTask: Task<Void, Never>?
    // ⚡️ 缓存 Dock 的 AXUIElement
    private var dockElement: AXUIElement?
    
    // RAII Token for Observer cleanup
    private var observerToken: ObserverToken?
    
    // Health Check Timer
    private var healthCheckTimer: Timer?
    
    // MARK: - Lifecycle
    
    init() {
        // 初始扫描
        startMonitoring()
        startHealthCheck()
    }
    
    deinit {
        healthCheckTimer?.invalidate()
        // observerToken deinit will handle cleanup
    }
    
    // MARK: - Public Methods
    
    func startMonitoring() {
        guard observerToken == nil else { return }
        
        // 1. 找到 Dock 应用
        let dockApps = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == "com.apple.dock" }
        guard let app = dockApps.first else {
            print("⚠️ DockMonitor: 未找到 Dock 进程")
            return
        }
        self.dockApp = app
        
        // ⚡️ 缓存 Dock Element
        self.dockElement = AXUIElementCreateApplication(app.processIdentifier)
        
        // 2. 初始扫描
        performScan()
        
        // 3. 创建 AXObserver
        setupObserver(for: app.processIdentifier)
        
        // 4. 移除轮询 (已通过启发式刷新替代)
        // startPolling()
        
        // 5. 监听应用启动/退出，因为这会改变 Dock 布局
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(handleAppChange), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(handleAppChange), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        
        // ⚡️ 修复：监听本应用窗口最小化
        NotificationCenter.default.addObserver(self, selector: #selector(handleAppChange), name: NSWindow.didMiniaturizeNotification, object: nil)
    }
    
    func stopMonitoring() {
        observerToken = nil // This triggers deinit and cleanup
        
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
        dockApp = nil
        dockElement = nil
        scanTask?.cancel()
    }
    
    /// 强制刷新（例如在某些无法捕获的事件发生时）
    func refresh() {
        // 使用防抖，避免频繁调用
        debounceScan()
    }
    
    // MARK: - Private Methods
    
    private func startHealthCheck() {
        healthCheckTimer?.invalidate()
        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.performHealthCheck()
            }
        }
    }
    
    private func performHealthCheck() {
        // 检查当前跟踪的 Dock 进程是否仍然有效
        guard let currentDockApp = dockApp else {
            // 如果没有跟踪的 Dock，尝试重新启动监听
            startMonitoring()
            return
        }
        
        // 检查 Dock 进程是否已终止
        if currentDockApp.isTerminated {
            print("⚠️ DockMonitor: 检测到 Dock 进程已终止，正在重新连接...")
            stopMonitoring()
            startMonitoring()
            return
        }
        
        // 检查当前运行的 Dock 进程 PID 是否与我们跟踪的一致
        // (处理 killall Dock 后 PID 改变的情况)
        let runningDockApps = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == "com.apple.dock" }
        if let newDockApp = runningDockApps.first, newDockApp.processIdentifier != currentDockApp.processIdentifier {
            print("⚠️ DockMonitor: 检测到 Dock PID 变化 (Old: \(currentDockApp.processIdentifier), New: \(newDockApp.processIdentifier))，正在重新连接...")
            stopMonitoring()
            startMonitoring()
        }
    }
    
    // 移除 pollingTask
    
    private func setupObserver(for pid: pid_t) {
        // 创建观察者
        var observerRef: AXObserver?
        let error = AXObserverCreate(pid, { (observer, element, notification, refcon) in
            guard let refcon = refcon else { return }
            let monitor = Unmanaged<DockMonitor>.fromOpaque(refcon).takeUnretainedValue()
            
            // ⚡️ Fix: Capture monitor explicitly to avoid 'captured var' error
            Task { [monitor] in
                await MainActor.run {
                    monitor.handleNotification(notification as String)
                }
            }
            // 监听应用终止
            // ⚡️ 修复：使用 NSWorkspace 通知
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didTerminateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak monitor] notification in
                guard let monitor = monitor,
                      let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.bundleIdentifier == "com.apple.dock" else { return }
                
                Task { @MainActor in
                    monitor.handleDockTermination()
                }
            }
        }, &observerRef)
        
        guard error == .success, let observer = observerRef else {
            print("⚠️ DockMonitor: 创建 AXObserver 失败: \(error.rawValue)")
            return
        }
        
        
        // 获取 Dock 的 AXUIElement (使用缓存)
        guard let dockRef = self.dockElement else { return }
        
        // 添加通知监听
        // kAXLayoutChangedNotification 通常在 Dock 图标位置/大小改变时触发
        AXObserverAddNotification(observer, dockRef, kAXLayoutChangedNotification as CFString, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))
        
        // 监听子元素销毁（移除应用）
        AXObserverAddNotification(observer, dockRef, kAXUIElementDestroyedNotification as CFString, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))
        
        // 监听大小改变（Dock 大小调整）
        AXObserverAddNotification(observer, dockRef, kAXWindowResizedNotification as CFString, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))
        
        // ⚡️ 修复：监听 ElementBusy (通常在 Dock 动画/最小化时触发)
        AXObserverAddNotification(observer, dockRef, kAXElementBusyChangedNotification as CFString, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))
        
        // ⚡️ 修复：监听焦点变化 (作为 fallback)
        AXObserverAddNotification(observer, dockRef, kAXFocusedUIElementChangedNotification as CFString, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))
        
        // 将观察者添加到 RunLoop
        guard let runLoop = CFRunLoopGetCurrent() else { return }
        CFRunLoopAddSource(runLoop, AXObserverGetRunLoopSource(observer), .defaultMode)
        
        // Create Token
        self.observerToken = ObserverToken(observer: observer, element: dockRef, runLoop: runLoop)
        
        print("✅ DockMonitor: 开始监听 Dock 变化")
    }
    
    private func handleNotification(_ notification: String) {
        // print("🔔 DockMonitor: 收到通知 \(notification)")
        // 使用防抖进行扫描
        debounceScan()
    }
    
    private func debounceScan() {
        scanTask?.cancel()
        scanTask = Task {
            try? await Task.sleep(for: .milliseconds(200)) // 200ms 防抖
            if !Task.isCancelled {
                performScan()
            }
        }
    }
    
    @objc private func handleAppChange(_ notification: Notification) {
        // print("🔄 DockMonitor: 应用状态改变，刷新 Dock 布局")
        debounceScan()
    }
    
    private func performScan() {
        // 捕获缓存的 element 以便在 detached task 中使用
        // 注意：AXUIElement 是线程安全的 CoreFoundation 对象
        guard let dockRef = self.dockElement else { return }
        
        Task.detached {
            // ⚡️ 修复：处理扫描失败的情况 (返回 nil)
            guard let newIcons = await self.scanDockIcons(using: dockRef) else {
                print("⚠️ DockMonitor: 扫描失败 (可能是 Dock 忙碌)，保留旧数据")
                return
            }
            
            await MainActor.run {
                self.icons = newIcons
                print("🔄 DockMonitor: 更新了 \(newIcons.count) 个图标")
            }
        }
    }
    
    // ⚡️ 修复：添加 handleDockTermination 方法
    func handleDockTermination() {
        print("⚠️ DockMonitor: Dock 进程终止，停止监听并重置状态")
        stopMonitoring()
        
        // 尝试重新启动监听 (延迟执行)
        Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run {
                self.startMonitoring()
            }
        }
    }
    
    // 复用 WindowEngine 中的逻辑，但独立出来以便解耦
    // ⚡️ 修复：返回可选值，nil 表示扫描失败
    private func scanDockIcons(using dockRef: AXUIElement) async -> [DockIconInfo]? {
        var icons: [DockIconInfo] = []
        
        guard let children = AXUtils.getAXAttribute(dockRef, kAXChildrenAttribute, ofType: [AXUIElement].self) else {
            // ⚡️ 修复：获取子元素失败 (例如 Dock 正在动画)，返回 nil 而不是空数组
            return nil
        }
        
        for child in children {
            let role = AXUtils.getAXAttribute(child, kAXRoleAttribute, ofType: String.self)
            if role == "AXList" {
                guard let iconElements = AXUtils.getAXAttribute(child, kAXChildrenAttribute, ofType: [AXUIElement].self) else {
                    continue
                }
                for iconRef in iconElements {
                    if let info = AXUtils.extractDockIconInfo(iconRef) {
                        icons.append(info)
                    }
                }
            }
        }
        return icons
    }
}

// MARK: - Helper Classes

private final class ObserverToken: @unchecked Sendable {
    let observer: AXObserver
    let element: AXUIElement
    let runLoop: CFRunLoop
    
    init(observer: AXObserver, element: AXUIElement, runLoop: CFRunLoop) {
        self.observer = observer
        self.element = element
        self.runLoop = runLoop
    }
    
    deinit {
        let obs = observer
        let elem = element
        let rl = runLoop
        
        // Remove notifications
        AXObserverRemoveNotification(obs, elem, kAXLayoutChangedNotification as CFString)
        AXObserverRemoveNotification(obs, elem, kAXUIElementDestroyedNotification as CFString)
        AXObserverRemoveNotification(obs, elem, kAXWindowResizedNotification as CFString)
        AXObserverRemoveNotification(obs, elem, kAXElementBusyChangedNotification as CFString)
        AXObserverRemoveNotification(obs, elem, kAXFocusedUIElementChangedNotification as CFString)
        
        // Remove from runloop
        let source = AXObserverGetRunLoopSource(obs)
        CFRunLoopRemoveSource(rl, source, .defaultMode)
    }
}
