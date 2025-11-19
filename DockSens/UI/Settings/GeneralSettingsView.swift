//
//  GeneralSettingsView.swift
//  DockSens
//
//  Created by DockSens Team.
//

import SwiftUI
import ServiceManagement // 用于处理开机自启

struct GeneralSettingsView: View {
    // MARK: - Persistent Settings
    // 直接绑定 UserDefaults
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("showDockPreviews") private var showDockPreviews = true
    @AppStorage("dockPreviewDelay") private var dockPreviewDelay: Double = 0.2
    @AppStorage("previewSize") private var previewSize: Double = 1.0
    
    var body: some View {
        Form {
            Section {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        toggleLaunchAtLogin(enabled: newValue)
                    }
                
                Toggle("Show Dock Previews", isOn: $showDockPreviews)
            } header: {
                Text("Behavior")
            }
            
            Section("Preview Customization") {
                VStack(alignment: .leading) {
                    HStack {
                        Text("Hover Delay")
                        Spacer()
                        Text("\(dockPreviewDelay, specifier: "%.1f")s")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $dockPreviewDelay, in: 0...1.0, step: 0.1) {
                        Text("Delay")
                    } minimumValueLabel: {
                        Image(systemName: "hare")
                    } maximumValueLabel: {
                        Image(systemName: "tortoise")
                    }
                }
                .disabled(!showDockPreviews)
                
                VStack(alignment: .leading) {
                    HStack {
                        Text("Preview Size")
                        Spacer()
                        Text("\(Int(previewSize * 100))%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $previewSize, in: 0.5...1.5, step: 0.1)
                }
                .disabled(!showDockPreviews)
            }
        }
        .formStyle(.grouped)
        .frame(minHeight: 250)
    }
    
    // MARK: - Helper
    
    private func toggleLaunchAtLogin(enabled: Bool) {
        // macOS 13+ 推荐使用 SMAppService
        // 注意：这需要 App 开启 Sandbox 并在 Info.plist 注册
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to toggle launch at login: \(error)")
        }
    }
}

#Preview {
    GeneralSettingsView()
}