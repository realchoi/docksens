//
//  AppState.swift
//  DockSens
//
//  Created by DockSens Team.
//

import SwiftUI
import Observation

@MainActor
@Observable
final class AppState {
    var runningWindows: [WindowInfo] = []
    var isSwitcherVisible: Bool = false
    var isPro: Bool = false 
    
    private let windowManager = WindowManager()
    private let storeService = StoreService()
    private let windowSnapper = WindowSnapper()
    
    init() {
        Task { await startMonitoringWindows() }
        Task { await startMonitoringPurchases() }
        
        NotificationCenter.default.addObserver(forName: .toggleSwitcher, object: nil, queue: .main) { [weak self] _ in
            // ⚡️ 修复警告：显式使用 Task { @MainActor } 包裹调用
            Task { @MainActor [weak self] in
                self?.toggleSwitcher()
            }
        }
    }
    
    private func startMonitoringWindows() async {
        for await windows in windowManager.windowsStream() {
            self.runningWindows = windows
        }
    }
    
    private func startMonitoringPurchases() async {
        for await status in storeService.proStatusStream() {
            self.isPro = status
        }
    }
    
    func toggleSwitcher() {
        // 1. 权限检查
        guard WindowEngine.checkAccessibilityPermission() else {
            let alert = NSAlert()
            // 修改点：使用 String(localized:) 显式进行本地化
            alert.messageText = String(localized: "Permissions Missing")
            alert.informativeText = String(localized: "DockSens needs Accessibility permissions.")
            alert.addButton(withTitle: String(localized: "Open Settings"))
            alert.addButton(withTitle: String(localized: "Cancel"))
            
            if alert.runModal() == .alertFirstButtonReturn {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
            return
        }

        // 2. 切换逻辑
        guard !isSwitcherVisible else { 
            // 如果当前已经是显示状态，则触发隐藏
            print("AppState: Toggle -> Hide")
            windowManager.hideSwitcher()
            // 注意：这里不需要手动设为 false，因为 hideSwitcher 会触发下面的 onWindowClose 回调
            return
        }
        
        print("AppState: Toggle -> Show")
        // 手动设为 true，防止重复触发
        isSwitcherVisible = true
        
        // 3. 显示并监听关闭
        windowManager.showSwitcher { [weak self] in
            Task { @MainActor in
                print("AppState: Switcher Closed (Callback Received)")
                self?.isSwitcherVisible = false
            }
        }
    }
    
    // MARK: - Window Snapping

    func snapActiveWindow(to position: SnapPosition) {
        // 同步调用，不使用 Task，避免并发问题
        windowSnapper.snapActiveWindow(to: position)
    }
}