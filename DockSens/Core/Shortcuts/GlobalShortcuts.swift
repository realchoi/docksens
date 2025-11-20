//
//  GlobalShortcuts.swift
//  DockSens
//
//  Created by DockSens Team.
//

import AppKit
import AppIntents
import KeyboardShortcuts // 确保已添加 Swift Package Dependency

// MARK: - 1. 定义快捷键名称
// 文档引用: https://github.com/sindresorhus/KeyboardShortcuts#usage

extension KeyboardShortcuts.Name {
    // 窗口切换器 (Alt-Tab)
    static let toggleSwitcher = Self("toggleSwitcher", default: .init(.tab, modifiers: [.option]))
    
    // 窗口管理 (分屏)
    static let splitLeft = Self("splitLeft", default: .init(.leftArrow, modifiers: [.option, .command]))
    static let splitRight = Self("splitRight", default: .init(.rightArrow, modifiers: [.option, .command]))
    static let maximizeWindow = Self("maximizeWindow", default: .init(.return, modifiers: [.option, .command]))
    
    // 更多功能...
    static let centerWindow = Self("centerWindow", default: .init(.downArrow, modifiers: [.option, .command]))
}

// MARK: - 2. App Intents 集成 (用于快捷指令/Siri)

struct ToggleSwitcherIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Window Switcher"
    
    @MainActor
    func perform() async throws -> some IntentResult {
        // 注意：实际触发逻辑需要在 App 层面连接 AppState
        // 这里仅作为 Intent 定义
        return .result()
    }
}