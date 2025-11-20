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
        // ⚡️ 修复2：使用 WindowGroup + ID 替代 Settings Scene
        // 这允许我们通过 openWindow 程序化地可靠打开它
        WindowGroup(id: "settings") {
            SettingsView()
                .environment(appState)
                .frame(minWidth: 550, minHeight: 400)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        
        // 引导窗口
        WindowGroup {
            ZStack {
                if !hasCompletedOnboarding {
                    OnboardingView()
                        .environment(appState)
                        .frame(minWidth: 700, minHeight: 500)
                        .onAppear {
                            NSApp.activate(ignoringOtherApps: true)
                        }
                } else {
                    // 引导完成后，关闭此临时窗口
                    Color.clear
                        .onAppear {
                            // 查找除了 Settings 之外的窗口并关闭
                            for window in NSApp.windows {
                                if window.identifier?.rawValue != "settings" {
                                    window.close()
                                }
                            }
                        }
                }
            }
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 0, height: 0) // 尽可能隐形
        
        // 菜单栏图标
        MenuBarExtra("DockSens", systemImage: "macwindow.on.rectangle") {
            // ⚡️ 将内容提取到单独的 View，以便使用 Environment
            DockSensMenu(appState: appState, showDockPreviews: $showDockPreviews)
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

// ⚡️ 独立的菜单视图，支持 openWindow
struct DockSensMenu: View {
    @Environment(\.openWindow) var openWindow
    var appState: AppState
    @Binding var showDockPreviews: Bool
    
    var body: some View {
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
            // ⚡️ 使用 openWindow 可靠地打开设置窗口
            openWindow(id: "settings")
            // Agent App 需要强行激活自己才能让窗口置顶
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        Button("退出 DockSens") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: [.command])
    }
}

extension Notification.Name {
    static let toggleSwitcher = Notification.Name("ToggleSwitcherRequest")
}