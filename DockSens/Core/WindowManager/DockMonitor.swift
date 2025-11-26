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
    
    // MARK: - Private Properties
    
    private var observer: AXObserver?
    private var dockApp: NSRunningApplication?
    private var scanTask: Task<Void, Never>?
    // ⚡️ 缓存 Dock 的 AXUIElement
    private var dockElement: AXUIElement?
    
    // MARK: - Lifecycle
    
    init() {
        // 初始扫描
        startMonitoring()
    }
    
    // MARK: - Public Methods
    
    func startMonitoring() {
        guard observer == nil else { return }
        
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
    }
    
    func stopMonitoring() {
        if let observer = observer, let app = dockApp {
            let dockRef = AXUIElementCreateApplication(app.processIdentifier)
            AXObserverRemoveNotification(observer, dockRef, kAXLayoutChangedNotification as CFString)
            // 尝试移除其他可能添加的通知
            AXObserverRemoveNotification(observer, dockRef, kAXUIElementDestroyedNotification as CFString)
            AXObserverRemoveNotification(observer, dockRef, kAXWindowResizedNotification as CFString)
        }
        observer = nil
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
    
    // 移除 pollingTask
    
    private func setupObserver(for pid: pid_t) {
        // 创建观察者
        var observerRef: AXObserver?
        let error = AXObserverCreate(pid, { (observer, element, notification, refcon) in
            guard let refcon = refcon else { return }
            let monitor = Unmanaged<DockMonitor>.fromOpaque(refcon).takeUnretainedValue()
            
            Task { @MainActor in
                monitor.handleNotification(notification as String)
            }
        }, &observerRef)
        
        guard error == .success, let observer = observerRef else {
            print("⚠️ DockMonitor: 创建 AXObserver 失败: \(error.rawValue)")
            return
        }
        
        self.observer = observer
        
        // 获取 Dock 的 AXUIElement (使用缓存)
        guard let dockRef = self.dockElement else { return }
        
        // 添加通知监听
        // kAXLayoutChangedNotification 通常在 Dock 图标位置/大小改变时触发
        AXObserverAddNotification(observer, dockRef, kAXLayoutChangedNotification as CFString, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))
        
        // 监听子元素销毁（移除应用）
        AXObserverAddNotification(observer, dockRef, kAXUIElementDestroyedNotification as CFString, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))
        
        // 监听大小改变（Dock 大小调整）
        AXObserverAddNotification(observer, dockRef, kAXWindowResizedNotification as CFString, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))
        
        // 将观察者添加到 RunLoop
        CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
        
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
    
    private func performScan() {
        // 捕获缓存的 element 以便在 detached task 中使用
        // 注意：AXUIElement 是线程安全的 CoreFoundation 对象
        guard let dockRef = self.dockElement else { return }
        
        Task.detached {
            let newIcons = await self.scanDockIcons(using: dockRef)
            await MainActor.run {
                self.icons = newIcons
                print("🔄 DockMonitor: 更新了 \(newIcons.count) 个图标")
            }
        }
    }
    
    // 复用 WindowEngine 中的逻辑，但独立出来以便解耦
    private func scanDockIcons(using dockRef: AXUIElement) async -> [DockIconInfo] {
        var icons: [DockIconInfo] = []
        
        guard let children = AXUtils.getAXAttribute(dockRef, kAXChildrenAttribute, ofType: [AXUIElement].self) else {
            return []
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
