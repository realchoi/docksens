//
//  GeneralSettingsView.swift
//  DockSens
//
//  Created by DockSens Team.
//

import SwiftUI
import ServiceManagement

struct GeneralSettingsView: View {
    // MARK: - Persistent Settings
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("showDockPreviews") private var showDockPreviews = true
    @AppStorage("dockPreviewDelay") private var dockPreviewDelay: Double = 0.2
    @AppStorage("previewSize") private var previewSize: Double = 1.0
    
    // 语言设置状态
    // ⚡️ 修复：通过检查 App 专属域来正确判断是否设置了 override。
    // 如果直接用 UserDefaults.standard.array(...)，当 key 被移除时会 fallback 到系统语言(如 zh-Hans-CN)，
    // 导致与 Picker 的 tag (nil) 不匹配，从而显示空白。
    @State private var selectedLanguage: String? = {
        guard let bundleID = Bundle.main.bundleIdentifier,
              let defaults = UserDefaults.standard.persistentDomain(forName: bundleID),
              let languages = defaults["AppleLanguages"] as? [String],
              let first = languages.first else {
            return nil // 没有显式设置过 -> 跟随系统
        }
        return first
    }()
    
    @State private var showRestartAlert = false
    
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
            
            Section("Language") {
                Picker("App Language", selection: $selectedLanguage) {
                    Text("System Default").tag(nil as String?)
                    Text("English").tag("en" as String?)
                    Text("Simplified Chinese").tag("zh-Hans" as String?)
                }
                .onChange(of: selectedLanguage) { _, newValue in
                    updateLanguage(newValue)
                }
                
                if showRestartAlert {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text("Restart Required to Apply Changes")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Restart Now") {
                            restartApp()
                        }
                        .controlSize(.small)
                    }
                    .padding(.top, 4)
                }
            }
            
            Section("Preview Customization") {
                VStack(alignment: .leading) {
                    HStack(alignment: .center) {
                        Text("Hover Delay")
                        Spacer()
                        Text("\(dockPreviewDelay, specifier: "%.1f")s")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    
                    Slider(value: $dockPreviewDelay, in: 0...1.0, step: 0.1) {
                        EmptyView()
                    } minimumValueLabel: {
                        Image(systemName: "hare")
                    } maximumValueLabel: {
                        Image(systemName: "tortoise")
                    }
                }
                .disabled(!showDockPreviews)
                
                VStack(alignment: .leading) {
                    HStack(alignment: .center) {
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
        .frame(minHeight: 350)
    }
    
    // MARK: - Helpers
    
    private func updateLanguage(_ languageCode: String?) {
        if let code = languageCode {
            UserDefaults.standard.set([code], forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
        withAnimation {
            showRestartAlert = true
        }
    }
    
    private func restartApp() {
        guard let resourcePath = Bundle.main.resourcePath else { return }
        let url = URL(fileURLWithPath: resourcePath)
        let path = url.deletingLastPathComponent().deletingLastPathComponent().absoluteString
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["-n", path]
        task.launch()
        NSApplication.shared.terminate(self)
    }
    
    private func toggleLaunchAtLogin(enabled: Bool) {
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