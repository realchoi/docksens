//
//  WindowManager.swift
//  DockSens
//
//  Created by DockSens Team.
//

import AppKit
import Foundation
import Combine

@MainActor
class WindowManager {
    
    private var switcherController: SwitcherPanelController?
    private let engine = WindowEngine()
    private var windowContinuation: AsyncStream<[WindowInfo]>.Continuation?
    
    // MARK: - MRU Tracking (New)
    // 历史记录栈：存放最近激活过的 App PID，越靠前越新
    private var mruPIDs: [pid_t] = []
    private var observer: NSObjectProtocol?
    
    init() {
        setupMRUTracking()
    }
    
    deinit {
        if let observer = observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }
    
    // MARK: - Public Methods
    
    /// 显示 Alt-Tab 切换器
    /// - Parameter onWindowClose: 当窗口关闭（无论是用户取消还是选中）时触发的回调
    func showSwitcher(onWindowClose: @escaping () -> Void) {
        print("WindowManager: Show Switcher requested")
        
        Task {
            do {
                // 1. 获取原始数据 (基于 Z-Order)
                // 注意：WindowEngine 已经排除了 DockSens 自身
                let rawWindows = try await engine.activeWindows()
                
                // 2. 应用 MRU 排序算法
                // 逻辑：如果在 mruPIDs 里，按 MRU 顺序排；如果不在，保持原有 Z-Order 并在最后
                let sortedWindows = rawWindows.sorted { w1, w2 in
                    let idx1 = mruPIDs.firstIndex(of: w1.pid) ?? Int.max
                    let idx2 = mruPIDs.firstIndex(of: w2.pid) ?? Int.max
                    
                    if idx1 != idx2 {
                        return idx1 < idx2 // MRU 优先 (index 越小越靠前)
                    } else {
                        // 如果 App 相同或都不在 MRU 列表里，保持原始稳定性 (Z-Order)
                        // 使用原始数组中的索引来比较
                        let rawIdx1 = rawWindows.firstIndex(where: {$0.id == w1.id}) ?? Int.max
                        let rawIdx2 = rawWindows.firstIndex(where: {$0.id == w2.id}) ?? Int.max
                        return rawIdx1 < rawIdx2
                    }
                }
                
                // 3. 初始化控制器
                if switcherController == nil {
                    switcherController = SwitcherPanelController()
                }
                
                // 4. 绑定关闭回调
                switcherController?.onClose = {
                    onWindowClose()
                }
                
                // 5. 显示 (使用排序后的窗口列表)
                switcherController?.show(windows: sortedWindows)
                
            } catch {
                print("❌ WindowManager: Failed to fetch windows - \(error)")
                onWindowClose()
            }
        }
    }
    
    func hideSwitcher() {
        print("WindowManager: Hide Switcher requested")
        switcherController?.hide()
    }
    
    func windowsStream() -> AsyncStream<[WindowInfo]> {
        return AsyncStream { continuation in
            self.windowContinuation = continuation
        }
    }
    
    func refreshWindows() async {
        guard WindowEngine.checkAccessibilityPermission() else { return }
        do {
            let windows = try await engine.activeWindows()
            windowContinuation?.yield(windows)
        } catch {
            print("Scan error: \(error)")
        }
    }
    
    // MARK: - MRU Logic
    
    private func setupMRUTracking() {
        // 初始填充：把当前运行的 App 加进去，作为一个基准
        mruPIDs = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .map { $0.processIdentifier }
        
        // 监听 App 激活事件
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // ⚡️ 修复警告：使用 Task { @MainActor } 包裹闭包逻辑
            // 即使 queue 是 .main，Swift 编译器也需要显式上下文切换
            Task { @MainActor [weak self] in
                guard let self = self,
                      let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                    return
                }
                self.updateMRU(with: app.processIdentifier)
            }
        }
    }
    
    private func updateMRU(with pid: pid_t) {
        // 排除 DockSens 自己，防止它干扰排序
        if pid == ProcessInfo.processInfo.processIdentifier { return }
        
        // 算法：移除旧的，插入到队首
        if let index = mruPIDs.firstIndex(of: pid) {
            mruPIDs.remove(at: index)
        }
        mruPIDs.insert(pid, at: 0)
        
        // 限制列表长度，防止无限增长
        if mruPIDs.count > 50 {
            mruPIDs = Array(mruPIDs.prefix(50))
        }
    }
}