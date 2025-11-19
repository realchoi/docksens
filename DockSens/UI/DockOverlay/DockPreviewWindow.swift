//
//  DockPreviewWindow.swift
//  DockSens
//
//  Created by DockSens Team.
//

import SwiftUI
import AppKit

// MARK: - SwiftUI View

struct DockPreviewOverlay: View {
    let iconTitle: String
    let windows: [WindowInfo] // 该 App 关联的窗口缩略图数据
    
    var body: some View {
        VStack(spacing: 12) {
            // 标题栏
            HStack {
                Image(systemName: "app.window")
                    .symbolEffect(.bounce, value: iconTitle) // 动画效果
                Text(iconTitle)
                    .font(.headline)
                    .fontWeight(.medium)
                Spacer()
            }
            .padding(.horizontal, 4)
            
            // 缩略图网格
            // 使用 containerRelativeFrame 进行优雅布局
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    if windows.isEmpty {
                        Text("No Active Windows")
                            .foregroundStyle(.secondary)
                            .frame(width: 200, height: 120)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        ForEach(windows) { window in
                            WindowThumbnailCard(window: window)
                                .containerRelativeFrame(.horizontal, count: windows.count > 1 ? 2 : 1, spacing: 16)
                        }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned) // 贴靠滚动
            .frame(height: 140)
        }
        .padding(16)
        .background(.regularMaterial) // 毛玻璃背景
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
        // 触感反馈：当视图出现或数据变化时
        .sensoryFeedback(.selection, trigger: iconTitle)
    }
}

struct WindowThumbnailCard: View {
    let window: WindowInfo
    
    var body: some View {
        VStack {
            // 占位符：实际应显示 CGWindowListCreateImage 生成的截图
            Rectangle()
                .fill(Color.blue.gradient.opacity(0.3))
                .overlay {
                    Image(systemName: "macwindow")
                        .font(.largeTitle)
                        .foregroundStyle(.white)
                }
            
            Text(window.title)
                .font(.caption)
                .lineLimit(1)
                .padding(.top, 4)
        }
        .frame(height: 120)
        .background(Color.black.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - NSPanel Controller

/// 管理悬浮窗生命周期的控制器
@MainActor
class DockPreviewPanelController {
    private var panel: NSPanel!
    
    init() {
        setupPanel()
    }
    
    private func setupPanel() {
        // 创建一个完全透明、无边框的面板
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless, .hudWindow], // HUD 风格自带一些阴影和圆角处理
            backing: .buffered,
            defer: false
        )
        
        panel.level = .floating // 悬浮层级
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
    }
    
    /// 更新内容并显示在指定位置
    func show(for icon: DockIconInfo, windows: [WindowInfo]) {
        // 1. 创建 HostingController
        let rootView = DockPreviewOverlay(iconTitle: icon.title, windows: windows)
        let hostingView = NSHostingView(rootView: rootView)
        
        // 2. 计算尺寸
        let panelSize = hostingView.fittingSize
        panel.contentView = hostingView
        
        // 3. 计算位置 (居中显示在 Icon 上方)
        // 注意：icon.frame 是 Quartz 坐标 (Top-Left)，NSWindow 是 Cocoa 坐标 (Bottom-Left)
        guard let screen = NSScreen.main else { return }
        
        let iconCenterX = icon.frame.midX
        // icon.frame.minY 在 Quartz 中是大数值(底部)，转换为 Cocoa 需翻转
        // 简单计算：Dock 在底部，Icon 顶部 Y 坐标在 Cocoa 中就是 Dock 高度
        // 这里简化逻辑：直接取 Icon 顶部上方 10pt
        
        // 坐标转换
        let iconRectCocoa = CGRect(
            x: icon.frame.origin.x,
            y: screen.frame.height - (icon.frame.origin.y + icon.frame.height),
            width: icon.frame.width,
            height: icon.frame.height
        )
        
        let panelX = iconCenterX - (panelSize.width / 2)
        let panelY = iconRectCocoa.maxY + 15 // 图标上方 15pt
        
        let panelRect = CGRect(x: panelX, y: panelY, width: panelSize.width, height: panelSize.height)
        
        // 4. 设置 Frame 并显示 (不获取焦点)
        panel.setFrame(panelRect, display: true)
        panel.orderFront(nil) // 关键：显示但不激活
    }
    
    func hide() {
        panel.orderOut(nil)
    }
}