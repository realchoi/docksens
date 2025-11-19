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
        MenuBarExtra("DockSens", systemImage: "macwindow.on.rectangle") {
            // 1. 状态指示
            Button("DockSens 正在运行") { }
                .disabled(true)
            
            Divider()
            
            // 2. 快速开关
            Button {
                showDockPreviews.toggle()
            } label: {
                Text(showDockPreviews ? "暂停预览" : "恢复预览")
            }
            
            // 3. 窗口切换器
            Button("切换窗口") {
                Task { @MainActor in
                    appState.toggleSwitcher()
                }
            }
            
            Divider()
            
            // 4. 打开设置
            Button("设置...") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                NSApp.activate(ignoringOtherApps: true)
            }
            
            Divider()
            
            // 5. 退出应用 (修复：确保此按钮始终可见)
            Button("退出 DockSens") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: [.command])
        }
    }
    
    // MARK: - Logic
    
    /// 初始化全局快捷键监听
    private func setupShortcuts() {
        KeyboardShortcuts.onKeyUp(for: .toggleSwitcher) {
            Task { @MainActor in
                appState.toggleSwitcher()
            }
        }
        
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