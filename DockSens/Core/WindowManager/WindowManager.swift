//
//  WindowManager.swift
//  DockSens
//
//  Created by DockSens Team.
//

import AppKit
import Foundation
import Combine

/// 主线程窗口控制器
/// 负责协调 UI 与后台 WindowEngine 的交互，管理窗口数据的生命周期
@MainActor
class WindowManager {
    
    // MARK: - Properties
    
    /// Alt-Tab 切换器的窗口实例 (NSPanel)
    private var switcherPanel: NSPanel?
    
    /// 持有后台 Actor 实例，用于执行繁重的 AX 查询
    private let engine = WindowEngine()
    
    /// 数据流 Continuation，用于向 AppState 推送更新
    private var windowContinuation: AsyncStream<[WindowInfo]>.Continuation?
    
    // MARK: - Initialization
    
    init() {
        // 初始化时可以做一些配置，例如监听屏幕变化通知
    }
    
    // MARK: - Public Methods
    
    /// 显示 Alt-Tab 切换器
    func showSwitcher() {
        print("WindowManager: Show Switcher requested")
        // TODO: 在此处初始化 SwitcherWindow 并显示
        // if switcherPanel == nil { setupSwitcherPanel() }
        // switcherPanel?.makeKeyAndOrderFront(nil)
    }
    
    /// 隐藏 Alt-Tab 切换器
    func hideSwitcher() {
        switcherPanel?.orderOut(nil)
    }
    
    /// 创建一个异步流，供 AppState 监听窗口数据变化
    /// AppState 通过此流接收来自后台的最新窗口列表
    func windowsStream() -> AsyncStream<[WindowInfo]> {
        return AsyncStream { continuation in
            self.windowContinuation = continuation
        }
    }
    
    /// 触发一次窗口刷新
    /// 流程：检查权限 -> 后台扫描 -> 主线程推送数据
    func refreshWindows() async {
        // 1. 权限守卫：检查辅助功能权限
        // 注意：WindowEngine.checkAccessibilityPermission 是 nonisolated 的，可直接调用
        guard WindowEngine.checkAccessibilityPermission() else {
            print("⚠️ WindowManager: 缺少辅助功能权限，无法扫描窗口。")
            // 在实际应用中，这里应该通知 UI 显示“请授予权限”的提示
            return
        }
        
        print("WindowManager: 开始后台扫描...")
        
        do {
            // 2. 跨 Actor 调用 (Await)
            // 这里的 await 会挂起当前任务，但不会阻塞主线程 UI 渲染
            let windows = try await engine.activeWindows()
            print("WindowManager: 扫描完成，发现 \(windows.count) 个窗口")
            
            // 3. 推送数据给所有监听者 (AppState)
            windowContinuation?.yield(windows)
            
        } catch {
            print("❌ WindowManager: 扫描出错 - \(error)")
        }
    }
}