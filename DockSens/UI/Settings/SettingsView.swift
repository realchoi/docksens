//
//  SettingsView.swift
//  DockSens
//
//  Created by DockSens Team.
//

import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) var appState
    
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .tag("general")
            
            ShortcutsSettingsView()
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }
                .tag("shortcuts")
            
            ProStoreView()
                .tabItem {
                    Label("Pro", systemImage: appState.isPro ? "star.fill" : "star")
                }
                .badge(appState.isPro ? nil : "NEW")
                .tag("pro")
        }
        // macOS Settings 标准宽度
        .frame(width: 550)
        .scenePadding()
    }
}

#Preview {
    SettingsView()
        .environment(AppState())
}