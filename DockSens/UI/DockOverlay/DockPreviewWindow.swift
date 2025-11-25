//
//  DockPreviewWindow.swift
//  DockSens
//
//  Created by DockSens Team.
//

import SwiftUI
import AppKit

// MARK: - Helper Views

/// Native NSVisualEffectView wrapper for authentic macOS materials
struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - SwiftUI View

struct DockPreviewOverlay: View {
    let iconTitle: String
    let windows: [WindowInfo]
    let onWindowActivate: (WindowInfo) -> Void

    var body: some View {
        // Modern, refined layout with window thumbnails only
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(windows) { window in
                    WindowThumbnailCard(window: window) {
                        onWindowActivate(window)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(Color.clear)  // 确保完全透明
        .background {
            // macOS-style vibrant background with refined materials
            ZStack {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                
                // Subtle gradient overlay for depth
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.08),
                        Color.white.opacity(0.03)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 24, x: 0, y: 12)
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        // Subtle feedback on appearance
        .sensoryFeedback(.selection, trigger: iconTitle)
    }
}

struct WindowThumbnailCard: View {
    let window: WindowInfo
    let onActivate: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 0) { // 紧凑布局，移除默认间距
            // 缩略图容器 - 严格固定尺寸确保居中
            ZStack(alignment: .center) {
                if let cgImage = window.image {
                    // 使用 GeometryReader 确保图片完全居中
                    GeometryReader { geometry in
                        Image(decorative: cgImage, scale: 1.0)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .position(
                                x: geometry.size.width / 2,
                                y: geometry.size.height / 2
                            )
                    }
                    .padding(8) // 增加图片与边缘的距离
                } else {
                    // 优雅的占位符
                    ZStack {
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.gray.opacity(0.15),
                                        Color.gray.opacity(0.08)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        
                        VStack(spacing: 6) {
                            Image(systemName: window.isMinimized ? "minus.circle" : "macwindow")
                                .font(.system(size: 32, weight: .light))
                                .foregroundStyle(.tertiary)
                            
                            if window.isMinimized {
                                Text("Minimized")
                                    .font(.caption2)
                                    .foregroundStyle(.quaternary)
                            }
                        }
                    }
                }
                
                // 悬浮边框 - 应用到整个容器
                if isHovered {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(.tint, lineWidth: 2)
                }
            }
            .frame(width: 260, height: 160, alignment: .center)  // 增大尺寸，提升空间利用率

            // 移除 clipShape 以保持缩略图直角，但保留外层圆角边框
            // .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .shadow(color: .black.opacity(isHovered ? 0.25 : 0.15), radius: isHovered ? 8 : 4, x: 0, y: 2)

            // 窗口标题
            Text(window.title.isEmpty ? window.appName : window.title)
                .font(.system(size: 11, weight: isHovered ? .medium : .regular))
                .lineLimit(1) // 限制为单行，更整洁
                .padding(.horizontal, 4)
                .padding(.vertical, 6) // 减少垂直间距
                .multilineTextAlignment(.center)
                .foregroundStyle(isHovered ? .primary : .secondary)
                .frame(width: 260)
        }
        .frame(width: 272, height: 192) // 适配新尺寸
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.smooth(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            onActivate()
        }
        .help(window.title.isEmpty ? window.appName : window.title)
    }
}

// MARK: - NSPanel Controller

/// 管理悬浮窗生命周期的控制器
@MainActor
class DockPreviewPanelController {
    private var panel: NSPanel!
    private var isMouseInside = false // 🔧 修复问题4：跟踪鼠标状态
    private var hideTask: Task<Void, Never>?
    
    // 回调：通知外部鼠标是否在预览窗口内
    var onHoverStateChanged: ((Bool) -> Void)?

    init() {
        setupPanel()
    }

    private func setupPanel() {
        // 创建一个完全透明、无边框的面板
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless], // 移除 .hudWindow 以避免系统默认背景
            backing: .buffered,
            defer: false
        )

        panel.level = .popUpMenu  // 更高层级，覆盖系统 tooltip
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false  // 禁用系统 shadow，避免黑色框线
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        panel.acceptsMouseMovedEvents = true
    }

    /// 更新内容并显示在指定位置
    func show(for icon: DockIconInfo, windows: [WindowInfo], onWindowActivate: @escaping (WindowInfo) -> Void) {
        // 1. 创建带鼠标跟踪的视图
        let rootView = DockPreviewOverlay(iconTitle: icon.title, windows: windows, onWindowActivate: onWindowActivate)
            .onHover { [weak self] hovering in
                if hovering {
                    self?.cancelScheduledHide()
                    self?.isMouseInside = true
                    self?.onHoverStateChanged?(true) // 通知：鼠标进入
                } else {
                    self?.isMouseInside = false
                    self?.onHoverStateChanged?(false) // 通知：鼠标离开
                    self?.scheduleHide(delay: 0.2)
                }
            }

        let hostingView = NSHostingView(rootView: rootView)
        // 确保启用 layer 并设置透明背景
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.isOpaque = false

        // 2. 计算尺寸
        let panelSize = hostingView.fittingSize
        panel.contentView = hostingView

        // 3. 计算位置 - 覆盖系统 tooltip 文字，留下箭头
        guard let screen = NSScreen.main else { return }

        let iconCenterX = icon.frame.midX

        // 坐标转换为 Cocoa 坐标系
        let iconRectCocoa = CGRect(
            x: icon.frame.origin.x,
            y: screen.frame.height - (icon.frame.origin.y + icon.frame.height),
            width: icon.frame.width,
            height: icon.frame.height
        )

        // 系统 tooltip 的估算尺寸：
        // - 箭头高度约 6-8pt
        // - 文字区域高度约 18-22pt (取决于字体大小)
        // 我们的目标：让预览窗口底部正好覆盖文字部分，留出箭头
        
        let tooltipArrowHeight: CGFloat = 7  // 系统 tooltip 箭头高度
        let spacing: CGFloat = 2  // 负值让窗口向下移动，完全遮挡 tooltip 底边
        
        // 计算 Y 位置：Dock 图标上方 + 箭头高度 + 一点间距
        // 这样我们的窗口底部会正好在箭头顶部上方一点点
        let panelY = iconRectCocoa.maxY + tooltipArrowHeight + spacing
        
        // 水平居中对齐图标
        let panelX = iconCenterX - (panelSize.width / 2)

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