//
//  ShortcutsSettingsView.swift
//  DockSens
//
//  Created by DockSens Team.
//

import SwiftUI
import KeyboardShortcuts

struct ShortcutsSettingsView: View {
    var body: some View {
        Form {
            Section {
                // 使用 KeyboardShortcuts 提供的 Recorder 组件
                // 它可以自动处理按键捕获、显示和持久化
                KeyboardShortcuts.Recorder("Toggle Switcher", name: .toggleSwitcher)
                    .help("Show the active window switcher")
            } header: {
                Text("Core Features")
            } footer: {
                Text("Press keys to record new shortcut.")
            }
            
            Section("Window Management") {
                KeyboardShortcuts.Recorder("Split Left", name: .splitLeft)
                KeyboardShortcuts.Recorder("Split Right", name: .splitRight)
                KeyboardShortcuts.Recorder("Maximize", name: .maximizeWindow)
                KeyboardShortcuts.Recorder("Center", name: .centerWindow)
            }
            
            Section {
                Button("Reset All to Defaults") {
                    KeyboardShortcuts.reset(
                        .toggleSwitcher,
                        .splitLeft,
                        .splitRight,
                        .maximizeWindow,
                        .centerWindow
                    )
                }
                .controlSize(.small)
            }
        }
        .formStyle(.grouped) // macOS 风格的分组表单
        .frame(minHeight: 300)
    }
}

#Preview {
    ShortcutsSettingsView()
}