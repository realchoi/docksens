//
//  PermissionGrantView.swift
//  DockSens
//
//  Created by DockSens Team.
//

import SwiftUI

struct PermissionGrantView: View {
    // 注入管理器
    @State private var permissionManager = PermissionManager()
    
    // 这是一个绑定，用于通知父视图“完成”
    @Binding var isOnboardingFinished: Bool
    
    var body: some View {
        VStack(spacing: 30) {
            // Header
            VStack(spacing: 10) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue.gradient)
                
                Text("Permissions Required")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("DockSens needs these permissions to see your windows and provide previews.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            // Permission Rows Container
            VStack(spacing: 16) {
                // 1. 辅助功能权限
                PermissionRow(
                    title: "Accessibility",
                    description: "Required to detect window positions and Dock icons.",
                    icon: "figure.roll",
                    isGranted: permissionManager.isAccessibilityTrusted
                ) {
                    permissionManager.requestAccessibilityPermission()
                }
                
                Divider()
                
                // 2. 屏幕录制权限
                PermissionRow(
                    title: "Screen Recording",
                    description: "Required to capture window previews for the Dock.",
                    icon: "rectangle.dashed.badge.record",
                    isGranted: permissionManager.isScreenRecordingTrusted
                ) {
                    permissionManager.requestScreenRecordingPermission()
                }
            }
            .padding()
            .background(.regularMaterial) // 卡片背景
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(.white.opacity(0.1), lineWidth: 1)
            )
            .frame(maxWidth: 500)
            
            Spacer()
            
            // Action Area
            VStack(spacing: 12) {
                // 状态提示
                if permissionManager.allPermissionsGranted {
                    Text("All Set! You're ready to go.")
                        .foregroundStyle(.green)
                        .font(.headline)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    Text("Please grant permissions in System Settings")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                
                // 主按钮
                Button(action: {
                    withAnimation {
                        isOnboardingFinished = true
                    }
                }) {
                    Text("Start Using DockSens")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!permissionManager.allPermissionsGranted) // 核心逻辑：自动启用
                .frame(maxWidth: 300)
            }
        }
        .padding(40)
        // 生命周期监测
        .onAppear {
            permissionManager.startMonitoring()
        }
        .onDisappear {
            permissionManager.stopMonitoring()
        }
        // 当 App 从后台切回前台时，额外检查一次（作为双重保险）
        .onChange(of: ScenePhase.active) { _, _ in
            // 这里可以使用 notification center 触发一次强制检查，
            // 但 startMonitoring 中的 Task 已经涵盖了这种情况。
        }
    }
}

// 辅助子视图：单行权限状态
struct PermissionRow: View {
    let title: String
    let description: String
    let icon: String
    let isGranted: Bool
    let action: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            // Icon
            Image(systemName: icon)
                .font(.title2)
                .frame(width: 40, height: 40)
                .background(isGranted ? Color.green.opacity(0.1) : Color.blue.opacity(0.1))
                .foregroundStyle(isGranted ? .green : .blue)
                .clipShape(Circle())
            
            // Text
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Status Indicator / Button
            if isGranted {
                HStack {
                    Text("Granted")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Image(systemName: "checkmark.circle.fill")
                }
                .foregroundStyle(.green)
                .transition(.scale.combined(with: .opacity))
            } else {
                Button("Enable") {
                    action()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .animation(.snappy, value: isGranted) // 状态变化时的平滑动画
    }
}