//
//  PermissionManager.swift
//  DockSens
//
//  Created by DockSens Team.
//

import AppKit
import SwiftUI
import CoreGraphics

/// 权限状态管理器
/// 负责检查和请求 macOS 关键权限 (辅助功能 & 屏幕录制)
@MainActor
@Observable
class PermissionManager {
    
    // MARK: - Public State
    var isAccessibilityTrusted: Bool = false
    var isScreenRecordingTrusted: Bool = false
    
    // 计算属性：是否所有必要权限都已授予
    var allPermissionsGranted: Bool {
        isAccessibilityTrusted && isScreenRecordingTrusted
    }
    
    // MARK: - Private
    private var monitoringTask: Task<Void, Never>?
    
    init() {
        // 初始化时检查一次
        checkPermissions()
    }
    
    // MARK: - Public Methods
    
    /// 开始实时监测权限变化 (用于引导页)
    /// 当用户在系统设置中切换开关时，App 能立即感知
    func startMonitoring() {
        stopMonitoring() // 防止重复启动
        
        monitoringTask = Task {
            while !Task.isCancelled {
                checkPermissions()
                // 每 1 秒轮询一次
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
    
    /// 停止监测
    func stopMonitoring() {
        monitoringTask?.cancel()
        monitoringTask = nil
    }
    
    /// 请求辅助功能权限
    func requestAccessibilityPermission() {
        // FIX: 添加 .takeUnretainedValue() 以正确解包 Unmanaged<CFString>
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
    
    /// 请求屏幕录制权限 (用于 Dock 预览截图)
    func requestScreenRecordingPermission() {
        // CGRequestScreenCaptureAccess 会触发系统弹窗
        // 注意：macOS 可能需要重启 App 才能完全生效，但状态会即时更新
        CGRequestScreenCaptureAccess()
    }
    
    /// 打开系统设置的特定页面 (通用方法)
    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
            NSWorkspace.shared.open(url)
        }
    }
    
    // MARK: - Internal Checks
    
    private func checkPermissions() {
        // 1. 检查辅助功能
        let axTrusted = AXIsProcessTrusted()
        
        // 2. 检查屏幕录制
        // CGPreflightScreenCaptureAccess 返回 true 表示有权限或已请求过
        // 为了更严谨，通常结合 CGWindowListCreateImage 尝试截图 1x1 像素，
        // 但在引导页阶段，Preflight 通常足够用于 UI 状态显示。
        let screenTrusted = CGPreflightScreenCaptureAccess()
        
        // 只有状态发生变化时才触发 UI 更新 (Observation 自动处理 Diff)
        if axTrusted != isAccessibilityTrusted {
            isAccessibilityTrusted = axTrusted
        }
        
        if screenTrusted != isScreenRecordingTrusted {
            isScreenRecordingTrusted = screenTrusted
        }
    }
}