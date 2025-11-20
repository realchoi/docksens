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
    
    init() {
        setupShortcuts()
    }
    
    var body: some Scene {
        // 设置窗口 (独立 Scene)
        Settings {
            SettingsView()
                .environment(appState)
        }
        
        // 引导窗口
        // 注意：作为 Agent App，我们只在需要时显示 WindowGroup
        // 如果引导已完成，我们在这里返回一个 EmptyView 或者不常用的 Scene，
        // 但 SwiftUI 必须至少有一个 WindowGroup。
        // 这里的策略是：如果已完成，我们显示一个不可见的窗口并立即关闭它，或者干脆保留 StatusView 但不自动激活。
        // 更佳实践：Agent App 通常只保留 Settings，引导页也可以作为特殊窗口弹出。
        // 这里为了兼容现有结构，我们保留逻辑，但在 onAppear 处理激活。
        WindowGroup {
            ZStack {
                if !hasCompletedOnboarding {
                    OnboardingView()
                        .environment(appState)
                        .frame(minWidth: 700, minHeight: 500)
                        .onAppear {
                            // ⚡️ 关键：Agent App 启动时默认无焦点。
                            // 如果显示引导页，必须强行把自己拉到前台！
                            NSApp.activate(ignoringOtherApps: true)
                        }
                } else {
                    // 引导完成后，我们不需要主窗口常驻。
                    // 显示一个空视图，并在出现时关闭主窗口（只留菜单栏）
                    Color.clear
                        .onAppear {
                            // 关闭当前窗口，只保留菜单栏图标
                            NSApp.windows.first?.close()
                        }
                }
            }
        }
        .windowResizability(.contentSize)
        // 确保主窗口关闭后 App 不退出 (Agent 默认行为，但也显式指定一下)
        .defaultSize(width: 0, height: 0) 
        
        // 菜单栏图标
        MenuBarExtra("DockSens", systemImage: "macwindow.on.rectangle") {
            Button("DockSens Is Running") { }.disabled(true)
            Divider()
            Button {
                showDockPreviews.toggle()
            } label: {
                Text(showDockPreviews ? "暂停预览" : "恢复预览")
            }
            Button("切换窗口") {
                Task { @MainActor in appState.toggleSwitcher() }
            }
            Divider()
            Button("设置...") {
                // 发送标准 Action 打开 Settings Scene
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                // ⚡️ Agent 打开窗口时必须强行激活自己
                NSApp.activate(ignoringOtherApps: true)
            }
            Divider()
            Button("退出 DockSens") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: [.command])
        }
    }
    
    private func setupShortcuts() {
        KeyboardShortcuts.onKeyUp(for: .toggleSwitcher) {
            Task { @MainActor in
                NotificationCenter.default.post(name: .toggleSwitcher, object: nil)
            }
        }
    }
}

extension Notification.Name {
    static let toggleSwitcher = Notification.Name("ToggleSwitcherRequest")
}