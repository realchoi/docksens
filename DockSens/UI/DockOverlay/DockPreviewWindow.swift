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
    let onWindowActivate: (WindowInfo) -> Void

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
            // 🔧 修复问题3：简化布局，移除 containerRelativeFrame
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(windows) { window in
                        WindowThumbnailCard(window: window) {
                            onWindowActivate(window)
                        }
                        .frame(width: 220) // 固定宽度
                    }
                }
                .padding(.horizontal, 8)
            }
            .frame(height: 180) // 增加高度以容纳缩略图和标题
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
    let onActivate: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 8) {
            // 缩略图区域
            ZStack {
                if let cgImage = window.image {
                    // 显示真实的窗口截图
                    Image(decorative: cgImage, scale: 1.0)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(minWidth: 200, minHeight: 120) // 🔧 修复问题2：设置最小尺寸
                        .frame(maxWidth: 300, maxHeight: 200) // 限制最大尺寸
                } else {
                    // 降级显示：无截图时使用占位符
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(width: 200, height: 120) // 🔧 固定占位符尺寸
                        .overlay {
                            VStack(spacing: 8) {
                                Image(systemName: "macwindow")
                                    .font(.largeTitle)
                                    .foregroundStyle(.secondary)

                                if window.isMinimized {
                                    Text("Minimized")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                }

                // 悬浮时的遮罩效果
                if isHovered {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.blue.opacity(0.2))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // 窗口标题
            Text(window.title.isEmpty ? window.appName : window.title)
                .font(.caption)
                .lineLimit(1)
                .foregroundStyle(isHovered ? .primary : .secondary)
                .frame(maxWidth: 200) // 限制标题宽度
        }
        .padding(8)
        .background(isHovered ? Color.blue.opacity(0.1) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isHovered ? Color.blue : Color.clear, lineWidth: 2)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            onActivate()
        }
        .help(window.title) // 工具提示
    }
}

// MARK: - NSPanel Controller

/// 管理悬浮窗生命周期的控制器
@MainActor
class DockPreviewPanelController {
    private var panel: NSPanel!
    private var isMouseInside = false // 🔧 修复问题4：跟踪鼠标状态
    private var hideTask: Task<Void, Never>?

    init() {
        setupPanel()
    }

    private func setupPanel() {
        // 创建一个完全透明、无边框的面板
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless, .hudWindow],
            backing: .buffered,
            defer: false
        )

        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        panel.acceptsMouseMovedEvents = true // 接受鼠标移动事件
    }

    /// 更新内容并显示在指定位置
    func show(for icon: DockIconInfo, windows: [WindowInfo], onWindowActivate: @escaping (WindowInfo) -> Void) {
        // 1. 创建带鼠标跟踪的视图
        let rootView = DockPreviewOverlay(iconTitle: icon.title, windows: windows, onWindowActivate: onWindowActivate)
            .onHover { [weak self] hovering in
                // 🔧 修复问题4：使用 SwiftUI 的 onHover 跟踪鼠标
                if hovering {
                    self?.cancelScheduledHide()
                    self?.isMouseInside = true
                    print("🖱️ DockPreview: 鼠标进入预览面板")
                } else {
                    self?.isMouseInside = false
                    self?.scheduleHide(delay: 0.2)
                    print("🖱️ DockPreview: 鼠标离开预览面板")
                }
            }

        let hostingView = NSHostingView(rootView: rootView)

        // 2. 计算尺寸
        let panelSize = hostingView.fittingSize
        panel.contentView = hostingView

        // 3. 计算位置
        guard let screen = NSScreen.main else { return }

        let iconCenterX = icon.frame.midX

        // 坐标转换
        let iconRectCocoa = CGRect(
            x: icon.frame.origin.x,
            y: screen.frame.height - (icon.frame.origin.y + icon.frame.height),
            width: icon.frame.width,
            height: icon.frame.height
        )

        let panelX = iconCenterX - (panelSize.width / 2)
        let panelY = iconRectCocoa.maxY + 15

        let panelRect = CGRect(x: panelX, y: panelY, width: panelSize.width, height: panelSize.height)

        // 4. 设置 Frame 并显示
        panel.setFrame(panelRect, display: true)
        panel.orderFront(nil)

        // 5. 重置状态
        isMouseInside = false
        hideTask?.cancel()
    }

    func hide() {
        panel.orderOut(nil)
        isMouseInside = false
        hideTask?.cancel()
    }

    // 🔧 修复问题4：延迟隐藏
    func scheduleHide(delay: TimeInterval = 0.3) {
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            if !isMouseInside {
                self.hide()
            }
        }
    }

    func cancelScheduledHide() {
        hideTask?.cancel()
    }
}