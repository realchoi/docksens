//
//  WindowManager.swift
//  DockSens
//
//  Created by DockSens Team.
//

import AppKit
import Foundation
import Combine

@MainActor
class WindowManager {
    
    private var switcherController: SwitcherPanelController?
    private let engine = WindowEngine()
    private var windowContinuation: AsyncStream<[WindowInfo]>.Continuation?
    
    // MARK: - Window-Level MRU Tracking
    // 使用 "PID-Title" 组合作为窗口的稳定指纹
    private var mruSignatures: [String] = []
    private var observer: NSObjectProtocol?
    
    init() {
        setupSystemObservation()
    }
    
    deinit {
        if let observer = observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }
    
    // MARK: - Public Methods
    
    func showSwitcher(onWindowClose: @escaping () -> Void) {
        print("WindowManager: Show Switcher requested")
        
        Task {
            do {
                let rawWindows = try await engine.activeWindows()
                
                // ⚡️ 核心修复：基于窗口指纹的 MRU 排序
                // 解决 "同 App 窗口连带" 问题
                let sortedWindows = rawWindows.sorted { w1, w2 in
                    let sig1 = self.signature(for: w1)
                    let sig2 = self.signature(for: w2)
                    
                    let idx1 = mruSignatures.firstIndex(of: sig1) ?? Int.max
                    let idx2 = mruSignatures.firstIndex(of: sig2) ?? Int.max
                    
                    if idx1 != idx2 {
                        return idx1 < idx2 // 历史记录优先
                    } else {
                        // 如果都不在记录中，或者指纹相同，保持原始系统 Z-Order
                        // 使用 stableID (windowID) 辅助排序，确保稳定性
                        return w1.windowID > w2.windowID
                    }
                }
                
                if switcherController == nil {
                    switcherController = SwitcherPanelController()
                }
                
                switcherController?.onClose = {
                    onWindowClose()
                }
                
                // 传递 promoteWindow 回调：当用户选中窗口时，更新 MRU
                switcherController?.show(windows: sortedWindows, onSelect: { [weak self] selectedWindow in
                    self?.promoteWindow(selectedWindow)
                })
                
            } catch {
                print("❌ WindowManager: Failed to fetch windows - \(error)")
                onWindowClose()
            }
        }
    }
    
    func hideSwitcher() {
        switcherController?.hide()
    }
    
    func windowsStream() -> AsyncStream<[WindowInfo]> {
        return AsyncStream { continuation in
            self.windowContinuation = continuation
        }
    }
    
    func refreshWindows() async {
        guard WindowEngine.checkAccessibilityPermission() else { return }
        do {
            let windows = try await engine.activeWindows()
            windowContinuation?.yield(windows)
        } catch {
            print("Scan error: \(error)")
        }
    }
    
    // MARK: - MRU Logic
    
    private func signature(for window: WindowInfo) -> String {
        // 生成唯一指纹：PID + 标题
        // 即使 Frame 变了，只要标题没变，我们认为是同一个逻辑窗口
        return "\(window.pid)-\(window.title)"
    }
    
    // 当用户在 DockSens 中明确选中一个窗口时调用
    private func promoteWindow(_ window: WindowInfo) {
        let sig = signature(for: window)
        // 移除旧记录
        mruSignatures.removeAll { $0 == sig }
        // 插入队首
        mruSignatures.insert(sig, at: 0)
        
        // 限制长度
        if mruSignatures.count > 50 {
            mruSignatures = Array(mruSignatures.prefix(50))
        }
        
        print("✅ Promoted Window: \(sig)")
    }
    
    private func setupSystemObservation() {
        // 监听 App 激活 (作为辅助 MRU 更新)
        // 当用户通过 Dock 或 Cmd+Tab 切换 App 时，我们把该 App 的所有窗口指纹稍微提前，
        // 但不破坏 DockSens 内部精细的窗口排序。
        // 这里为了解决 Issue 2，我们**不再**在 App 激活时暴力重排整个 App 的窗口，
        // 而是信任系统的 Z-Order 变化，只有用户明确操作时才更新 mruSignatures。
        
        // (代码保留但留空，避免 App 级别干扰 Window 级别排序)
    }
}