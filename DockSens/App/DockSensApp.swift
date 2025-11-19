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
    // 1. 全局单一数据源 (Source of Truth)
    @State private var appState = AppState()
    
    // 2. 持久化存储：记录引导状态
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding: Bool = false
    
    // 3. 预览开关状态 (与 GeneralSettingsView 共享同一个 Key)
    @AppStorage("showDockPreviews") private var showDockPreviews: Bool = true
    
    var body: some Scene {
        // MARK: - Settings Window
        // macOS 标准偏好设置窗口 (Cmd+,)
        Settings {
            SettingsView()
                .environment(appState)
        }
        
        // MARK: - Main Window (Onboarding / Status)
        WindowGroup {
            Group {
                if !hasCompletedOnboarding {
                    // 引导流程：权限授予 -> 欢迎
                    OnboardingView()
                        .environment(appState)
                        .frame(minWidth: 700, minHeight: 500)
                } else {
                    // 引导完成后显示的简单状态页
                    StatusView()
                        .environment(appState)
                        .onAppear {
                            setupShortcuts()
                        }
                }
            }
        }
        .windowResizability(.contentSize)
        
        // MARK: - Menu Bar Item
        // FIX: 使用 SF Symbol 图标 macwindow.on.rectangle
        MenuBarExtra("DockSens", systemImage: "macwindow.on.rectangle") {
            // 1. 状态指示 (通常作为第一项，且不可点击)
            Button("DockSens 正在运行") { }
                .disabled(true)
            
            Divider()
            
            // 2. 快速开关 (暂停/恢复预览)
            Button {
                showDockPreviews.toggle()
            } label: {
                if showDockPreviews {
                    Text("暂停预览") // 当前开启，点击暂停
                } else {
                    Text("恢复预览") // 当前暂停，点击恢复
                }
            }
            
            // 3. 窗口切换器触发入口
            Button("切换窗口") {
                appState.toggleSwitcher()
            }
            .keyboardShortcut("w", modifiers: [.option, .command])
            
            Divider()
            
            // 4. 打开设置 (使用 SwiftUI 原生 API)
            SettingsLink {
                Text("设置...")
            }
            .keyboardShortcut(",", modifiers: [.command])
            
            Divider()
            
            // 5. 退出应用
            Button("退出 DockSens") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: [.command])
        }
    }
    
    // MARK: - Logic
    
    /// 初始化全局快捷键监听
    private func setupShortcuts() {
        // 绑定: 切换器 (Alt-Tab)
        KeyboardShortcuts.onKeyUp(for: .toggleSwitcher) {
            Task { @MainActor in
                appState.toggleSwitcher()
            }
        }
        
        // 绑定: 分屏 (示例逻辑)
        KeyboardShortcuts.onKeyUp(for: .splitLeft) {
            print("Shortcut: Split Left Triggered")
        }
        
        KeyboardShortcuts.onKeyUp(for: .splitRight) {
            print("Shortcut: Split Right Triggered")
        }
        
        KeyboardShortcuts.onKeyUp(for: .maximizeWindow) {
            print("Shortcut: Maximize Triggered")
        }
    }
}

// MARK: - Helper Views

/// 简单的运行状态视图
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
            
            HStack {
                // 使用 Button 模拟打开设置的行为 (因为 SettingsLink 只能在 Menu 中使用)
                Button("Open Settings") {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
                
                if !appState.isPro {
                    Button("Unlock Pro") {
                         NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.top, 10)
        }
        .padding(40)
        .frame(width: 400, height: 350)
        .background(.regularMaterial)
    }
}