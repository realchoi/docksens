//
        //  AppState.swift
        //  DockSens
        //
        //  Created by DockSens Setup Script.
        //

        import SwiftUI
import Observation

        // TODO: 全局单一事实来源。整合 WindowManager 和 StoreService 的状态。
        // ---------------------------------------------------------


@MainActor
@Observable
final class AppState {
    // --- 核心状态 ---
    var runningWindows: [WindowInfo] = []
    var isSwitcherVisible: Bool = false
    var isPro: Bool = false // 内购状态
    
    // --- 内部服务 ---
    private let windowManager = WindowManager()
    private let storeService = StoreService()
    
    init() {
        Task { await startMonitoringWindows() }
        Task { await startMonitoringPurchases() }
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
        guard !isSwitcherVisible else { 
            windowManager.hideSwitcher()
            isSwitcherVisible = false
            return
        }
        windowManager.showSwitcher()
        isSwitcherVisible = true
    }
}
