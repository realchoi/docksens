//
//  DockSensApp.swift
//  DockSens
//
//  Created by DockSens Team.
//

import SwiftUI
import AppIntents
import KeyboardShortcuts

@main
struct DockSensApp: App {
    // 1. 全局状态
    @State private var appState = AppState()
    
    // 2. 持久化设置
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding: Bool = false
    @AppStorage("showDockPreviews") private var showDockPreviews: Bool = true
    
    // 3. 初始化：确保 App 启动时立即注册快捷键
    init() {
        setupShortcuts()
    }
    
    var body: some Scene {
        // 设置窗口
        Settings {
            SettingsView()
                .environment(appState)
        }
        
        // 主窗口 (状态/引导)
        WindowGroup {
            Group {
                if !hasCompletedOnboarding {
                    OnboardingView()
                        .environment(appState)
                        .frame(minWidth: 700, minHeight: 500)
                } else {
                    StatusView()
                        .environment(appState)
                }
            }
        }
        .windowResizability(.contentSize)
        // ❌ 注意：这里不再需要 .alert(...)，因为我们改用 NSAlert 在 AppState 中直接弹窗
        
        // 菜单栏图标
        MenuBarExtra("DockSens", systemImage: "macwindow.on.rectangle") {
            Button("DockSens 正在运行") { }.disabled(true)
            Divider()
            Button {
                showDockPreviews.toggle()
            } label: {
                Text(showDockPreviews ? "暂停预览" : "恢复预览")
            }
            Button("切换窗口") {
                // 通过 Task 触发 MainActor 方法
                Task { @MainActor in appState.toggleSwitcher() }
            }
            Divider()
            Button("设置...") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                NSApp.activate(ignoringOtherApps: true)
            }
            Divider()
            Button("退出 DockSens") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: [.command])
        }
    }
    
    // 静态注册方法
    private func setupShortcuts() {
        KeyboardShortcuts.onKeyUp(for: .toggleSwitcher) {
            // 监听到快捷键 -> 发送通知 -> AppState 响应
            Task { @MainActor in
                NotificationCenter.default.post(name: .toggleSwitcher, object: nil)
            }
        }
    }
}

// 定义通知名称
extension Notification.Name {
    static let toggleSwitcher = Notification.Name("ToggleSwitcherRequest")
}

// StatusView 简单实现
struct StatusView: View {
    @Environment(AppState.self) var appState
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: true)
            
            VStack(spacing: 8) {
                Text("DockSens is Running")
                    .font(.title2.bold())
                
                Text("The app is active in your menu bar.\nYou can safely close this window.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button("Open Settings") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            .padding(.top, 10)
        }
        .padding(40)
        .frame(width: 400, height: 350)
        .background(.regularMaterial)
    }
}