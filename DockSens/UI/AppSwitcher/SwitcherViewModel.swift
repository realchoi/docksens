//
//  SwitcherViewModel.swift
//  DockSens
//
//  Created by DockSens Team.
//

import Foundation
import SwiftUI
import Combine

@MainActor
class SwitcherViewModel: ObservableObject, KeyboardInputDelegate {
    
    // MARK: - UI State
    @Published var windows: [WindowInfo] = []
    @Published var selectedIndex: Int = 0
    @Published var isVisible: Bool = false
    
    // MARK: - Dependencies
    private let inputManager = KeyboardInputManager()
    private var selectionCallback: ((WindowInfo) -> Void)?
    
    init() {
        inputManager.delegate = self
    }
    
    // MARK: - Public API
    
    func show(with windows: [WindowInfo], onSelect: @escaping (WindowInfo) -> Void) {
        self.windows = windows
        self.selectionCallback = onSelect
        
        // 默认选中第二个窗口 (符合 Alt-Tab 习惯：第一个通常是当前窗口)
        // 如果只有一个窗口，则选中第一个
        if windows.count > 1 {
            self.selectedIndex = 1
        } else {
            self.selectedIndex = 0
        }
        
        // 尝试启动键盘拦截
        // 即使失败也显示 UI，避免死锁
        if !inputManager.startMonitoring() {
            print("⚠️ SwitcherViewModel: Keyboard monitoring failed.")
        }
        
        withAnimation(.snappy) {
            self.isVisible = true
        }
    }
    
    func hide() {
        withAnimation(.easeOut(duration: 0.15)) {
            self.isVisible = false
        }
        // 延迟停止监听以配合动画
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.inputManager.stopMonitoring()
        }
    }
    
    // MARK: - KeyboardInputDelegate
    
    func handleNavigateLeft() {
        // 确保在主线程更新 UI
        guard !windows.isEmpty else { return }
        if selectedIndex > 0 {
            selectedIndex -= 1
        } else {
            selectedIndex = windows.count - 1 // 循环到末尾
        }
    }
    
    func handleNavigateRight() {
        guard !windows.isEmpty else { return }
        if selectedIndex < windows.count - 1 {
            selectedIndex += 1
        } else {
            selectedIndex = 0 // 循环到开头
        }
    }
    
    func handleSelect() {
        // 防止重复触发：只有当窗口可见时才响应
        guard isVisible else { return }
        
        guard windows.indices.contains(selectedIndex) else {
            hide() // 没有任何选中项，直接关闭
            return
        }
        
        let selectedWindow = windows[selectedIndex]
        hide()
        selectionCallback?(selectedWindow)
    }
    
    func handleCancel() {
        hide()
    }
}