//
//  SwitcherWindow.swift
//  DockSens
//
//  Created by DockSens Team.
//

import SwiftUI
import AppKit

// MARK: - SwiftUI View

struct SwitcherView: View {
    @ObservedObject var viewModel: SwitcherViewModel
    
    // 定义动画阶段
    enum SelectionPhase: CaseIterable {
        case identity // 原始状态
        case selected // 选中高亮放大
    }
    
    var body: some View {
        ZStack {
            if viewModel.isVisible {
                VStack(spacing: 24) {
                    Text("Switch Window")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    
                    HStack(spacing: 20) {
                        ForEach(Array(viewModel.windows.enumerated()), id: \.element.id) { index, window in
                            WindowItemView(
                                window: window,
                                isSelected: index == viewModel.selectedIndex
                            )
                            // PhaseAnimator 魔法：只在选中的 Item 上触发
                            .phaseAnimator([false, true], trigger: index == viewModel.selectedIndex) { content, phase in
                                content
                                    .scaleEffect(phase && index == viewModel.selectedIndex ? 1.05 : 1.0) // 选中时轻微放大
                                    .offset(y: phase && index == viewModel.selectedIndex ? -4 : 0) // 选中时轻微上浮
                            } animation: { phase in
                                // 使用 snappy 弹簧动画让交互更灵动
                                .snappy(duration: 0.3, extraBounce: 0.15) 
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(30)
                .background(.thinMaterial) // 核心要求：薄材质背景
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(.white.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.3), radius: 30, x: 0, y: 15)
                .transition(.scale(scale: 0.95).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 忽略鼠标点击背景关闭 (可选)
        .onTapGesture {
            // viewModel.hide()
        }
    }
}

struct WindowItemView: View {
    let window: WindowInfo
    let isSelected: Bool
    
    var body: some View {
        VStack(spacing: 12) {
            // 图标/缩略图区域
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
                
                Image(systemName: "macwindow") // 占位符
                    .font(.system(size: 48))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .shadow(radius: isSelected ? 8 : 0)
                
                // 应用角标
                if let appName = window.appName.first {
                    Text(String(appName))
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 20, height: 20)
                        .background(.white)
                        .foregroundStyle(.black)
                        .clipShape(Circle())
                        .offset(x: 24, y: 24)
                }
            }
            .frame(width: 80, height: 80)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
            
            // 标题
            Text(window.appName)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? .primary : .secondary)
                .lineLimit(1)
                .frame(width: 80)
        }
    }
}

// MARK: - Panel Controller

@MainActor
class SwitcherPanelController {
    private var panel: NSPanel!
    private let viewModel = SwitcherViewModel()
    
    init() {
        setupPanel()
    }
    
    private func setupPanel() {
        // 创建全屏透明面板作为容器，确保居中显示
        guard let screen = NSScreen.main else { return }
        
        panel = NSPanel(
            contentRect: screen.frame,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        
        // 关键设置
        panel.level = .modalPanel // 比普通悬浮窗更高，模拟系统级 UI
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false // 阴影由 SwiftUI 视图自己画
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        // 嵌入 SwiftUI
        let rootView = SwitcherView(viewModel: viewModel)
        panel.contentView = NSHostingView(rootView: rootView)
    }
    
    func show(windows: [WindowInfo]) {
        // 确保 Panel 覆盖全屏 (处理多显示器分辨率变化)
        if let screen = NSScreen.main {
            panel.setFrame(screen.frame, display: true)
        }
        
        viewModel.show(with: windows) { selectedWindow in
            print("User selected: \(selectedWindow.title)")
            // TODO: 调用 WindowEngine 激活该窗口
            self.activateWindow(selectedWindow)
        }
        
        panel.orderFront(nil)
    }
    
    func hide() {
        viewModel.hide()
        // 动画结束后隐藏 Panel
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.panel.orderOut(nil)
        }
    }
    
    private func activateWindow(_ window: WindowInfo) {
        // 简单实现：通过 NSRunningApplication 激活
        // 实际上应该结合 AXUIElementRaise 来处理具体窗口以确保只有目标窗口前置
        let app = NSWorkspace.shared.runningApplications.first(where: { $0.processIdentifier == window.pid })
        
        // FIX: macOS 14+ 废弃了 .activateIgnoringOtherApps，且无效果。
        // 直接调用 activate(options:)。由于此调用是在响应用户快捷键/点击，系统通常会允许前台激活。
        // 使用 .activateAllWindows 确保应用的所有窗口都变为活跃状态（类似点击 Dock 图标的行为）
        app?.activate(options: .activateAllWindows)
    }
}