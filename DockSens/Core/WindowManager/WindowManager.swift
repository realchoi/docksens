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
    
    init() {}
    
    // MARK: - Public Methods
    
    /// 显示 Alt-Tab 切换器
    /// - Parameter onWindowClose: 当窗口关闭（无论是用户取消还是选中）时触发的回调
    func showSwitcher(onWindowClose: @escaping () -> Void) {
        print("WindowManager: Show Switcher requested")
        
        Task {
            do {
                // 1. 获取数据
                let windows = try await engine.activeWindows()
                
                // 2. 初始化控制器
                if switcherController == nil {
                    switcherController = SwitcherPanelController()
                }
                
                // 3. 绑定关闭回调
                switcherController?.onClose = {
                    // 转发回调给 AppState
                    onWindowClose()
                }
                
                // 4. 显示
                switcherController?.show(windows: windows)
                
            } catch {
                print("❌ WindowManager: Failed to fetch windows - \(error)")
                // 如果出错，也要通知关闭以重置状态
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
}