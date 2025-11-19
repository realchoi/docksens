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
        guard !windows.isEmpty else { return }
        
        self.windows = windows
        self.selectionCallback = onSelect
        self.selectedIndex = 0 // 默认选中第一个 (或者第二个，如果是 Alt-Tab 行为)
        
        // 尝试启动键盘拦截
        if inputManager.startMonitoring() {
            withAnimation(.snappy) {
                self.isVisible = true
            }
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
    
    func handlenavigateLeft() {
        // 必须在 MainActor 执行
        Task { @MainActor in
            guard !windows.isEmpty else { return }
            if selectedIndex > 0 {
                selectedIndex -= 1
            } else {
                selectedIndex = windows.count - 1 // 循环到末尾
            }
        }
    }
    
    func handleNavigateRight() {
        Task { @MainActor in
            guard !windows.isEmpty else { return }
            if selectedIndex < windows.count - 1 {
                selectedIndex += 1
            } else {
                selectedIndex = 0 // 循环到开头
            }
        }
    }
    
    func handleSelect() {
        Task { @MainActor in
            guard windows.indices.contains(selectedIndex) else { return }
            let selectedWindow = windows[selectedIndex]
            hide()
            selectionCallback?(selectedWindow)
        }
    }
    
    func handleCancel() {
        Task { @MainActor in
            hide()
        }
    }
}