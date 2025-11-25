//
//  AppState.swift
//  DockSens
//
//  Created by DockSens Team.
//

import SwiftUI
import Observation

@MainActor
@Observable
final class AppState {
    var runningWindows: [WindowInfo] = []
    var isSwitcherVisible: Bool = false
    var isPro: Bool = false

    private let windowManager = WindowManager()
    private let storeService = StoreService()
    private let windowSnapper = WindowSnapper()
    private let windowActivator = WindowActivator()

    // Dock 预览相关
    private let dockHoverDetector: DockHoverDetector
    private let dockPreviewPanel = DockPreviewPanelController()
    private let windowEngine = WindowEngine()

    // Dock 点击相关 (Stage 4)
    private let dockClickDetector: DockClickDetector
    private let dockWindowController = DockWindowController()

    // 🔧 添加：跟踪最后点击时间，防止点击后立即显示预览
    private var lastClickTime: Date = .distantPast

    init() {
        // 初始化 DockHoverDetector（需要传入 engine）
        self.dockHoverDetector = DockHoverDetector(engine: windowEngine)
        // 初始化 DockClickDetector（需要传入 hoverDetector）
        self.dockClickDetector = DockClickDetector(hoverDetector: dockHoverDetector)

        Task { await startMonitoringWindows() }
        Task { await startMonitoringPurchases() }

        NotificationCenter.default.addObserver(forName: .toggleSwitcher, object: nil, queue: .main) { [weak self] _ in
            // ⚡️ 修复警告：显式使用 Task { @MainActor } 包裹调用
            Task { @MainActor [weak self] in
                self?.toggleSwitcher()
            }
        }

        // 启动 Dock 悬浮监听
        startDockHoverMonitoring()

        // 启动 Dock 点击监听 (Stage 4)
        startDockClickMonitoring()
        
        // 🔧 性能优化：当鼠标在预览窗口内时，暂停 Dock 悬浮检测
        dockPreviewPanel.onHoverStateChanged = { [weak self] isHovering in
            self?.dockHoverDetector.setExplicitlyPaused(isHovering)
        }
    }

    // MARK: - Dock Preview Management

    private func startDockHoverMonitoring() {
        dockHoverDetector.startMonitoring()

        // 使用轮询检测悬浮状态
        Task { @MainActor in
            var previousHoveredIcon: DockIconInfo? = nil

            while true {
                try? await Task.sleep(for: .milliseconds(100))

                let currentIcon = dockHoverDetector.hoveredIcon

                // 🔧 修复：检查是否在点击冷却时间内（1秒）
                let timeSinceClick = Date().timeIntervalSince(lastClickTime)
                if timeSinceClick < 1.0 {
                    // 点击后 1 秒内不显示预览，避免显示正在最小化的窗口
                    continue
                }

                if currentIcon?.id != previousHoveredIcon?.id {
                    if let icon = currentIcon, dockHoverDetector.isHovering {
                        // 开始悬浮在新图标上
                        await showDockPreview(for: icon)
                    } else {
                        // 🔧 修复问题4：离开 Dock 时延迟隐藏，给用户时间移动到预览面板
                        dockPreviewPanel.scheduleHide(delay: 0.3)
                    }
                    previousHoveredIcon = currentIcon
                }
            }
        }
    }

    private func showDockPreview(for icon: DockIconInfo) async {
        // 1. 查找对应的运行中应用
        guard let targetApp = findRunningApp(for: icon) else {
            // print("⚠️ DockPreview: 找不到应用 \(icon.title)")
            // 🔧 修复问题1：切换到无窗口应用时，必须隐藏之前的预览
            dockPreviewPanel.hide()
            return
        }

        // 获取该应用的所有窗口
        do {
            // ⚡️ 性能优化：仅获取目标应用的窗口，避免全量扫描
            let appWindows = try await windowEngine.windows(for: targetApp)

            // 过滤出真正有效的窗口（包括最小化窗口）
            let visibleWindows = appWindows.filter { window in
                // 1. 有实际的窗口 ID（不是虚拟窗口）
                guard window.windowID > 0 else { return false }
                // 2. 窗口有合理的尺寸
                guard window.frame.width > 50 && window.frame.height > 50 else { return false }
                return true
            }

            print("📱 DockPreview: 显示 \(icon.title) 的 \(visibleWindows.count) 个窗口（总共 \(appWindows.count) 个）")

            // 只有当应用有窗口时才显示预览
            guard !visibleWindows.isEmpty else {
                print("⏭️ DockPreview: \(icon.title) 没有窗口，隐藏预览")
                dockPreviewPanel.hide()
                return
            }

            // 显示预览面板
            dockPreviewPanel.show(for: icon, windows: visibleWindows) { [weak self] window in
                // 点击缩略图时激活窗口
                Task { @MainActor in
                    await self?.activateWindowFromPreview(window)
                }
            }
        } catch {
            print("⚠️ DockPreview: 获取窗口列表失败 - \(error)")
            // 🔧 修复：发生错误时也隐藏预览
            dockPreviewPanel.hide()
        }
    }

    // 辅助方法：查找对应的运行中应用
    private func findRunningApp(for icon: DockIconInfo) -> NSRunningApplication? {
        let apps = NSWorkspace.shared.runningApplications
        
        // 1. 尝试通过 URL 匹配 Bundle ID
        if let url = icon.url,
           let bundle = Bundle(url: url),
           let bundleID = bundle.bundleIdentifier {
            if let app = apps.first(where: { $0.bundleIdentifier == bundleID }) {
                return app
            }
        }
        
        // 2. 尝试通过 Title 匹配 (降级方案)
        return apps.first(where: { $0.localizedName == icon.title })
    }

    private func activateWindowFromPreview(_ window: WindowInfo) async {
        print("🎯 激活窗口: \(window.title)")
        await windowActivator.activateWindow(window)

        // 激活后隐藏预览
        dockPreviewPanel.hide()
    }

    // MARK: - Dock Click Management (Stage 4)

    private func startDockClickMonitoring() {
        dockClickDetector.startMonitoring()

        // 使用轮询检测点击
        Task { @MainActor in
            var lastProcessedIconId: Int? = nil
            var lastProcessTime: Date = .distantPast
            var isProcessing = false // 🔧 添加处理标志

            while true {
                try? await Task.sleep(for: .milliseconds(50))

                // 🔧 如果正在处理，跳过本次检测
                if isProcessing {
                    continue
                }
                
                // 🔧 处理右键点击：隐藏预览窗口
                if dockClickDetector.rightClickedIcon != nil {
                    print("🖱️ AppState: 检测到右键点击，隐藏预览")
                    dockPreviewPanel.hide()
                    
                    // 重置右键点击状态
                    dockClickDetector.rightClickedIcon = nil
                    
                    // 暂停悬浮检测，避免干扰右键菜单
                    dockHoverDetector.pauseHoverDetection()
                    continue
                }

                if let clickedIcon = dockClickDetector.clickedIcon {

                    // 🔧 修复：检查是否是新的点击
                    let now = Date()
                    let timeSinceLastProcess = now.timeIntervalSince(lastProcessTime)
                    let isSameIcon = (clickedIcon.id == lastProcessedIconId)

                    if isSameIcon && timeSinceLastProcess < 0.8 { // 🔧 增强：同一图标 800ms 防抖（原来是 500ms）
                        print("⏭️ AppState: 同一图标点击过快，忽略 (\(String(format: "%.3f", timeSinceLastProcess))s)")
                        continue
                    }

                    // 🔧 修复：不同图标也需要短暂防抖，避免误触
                    if !isSameIcon && timeSinceLastProcess < 0.3 { // 🔧 增强：不同图标 300ms 防抖（原来是 200ms）
                        print("⏭️ AppState: 切换图标过快，忽略 (\(String(format: "%.3f", timeSinceLastProcess))s)")
                        continue
                    }

                    // 🔧 关键修复：立即标记为正在处理，并清除 clickedIcon
                    isProcessing = true
                    lastProcessedIconId = clickedIcon.id
                    lastProcessTime = now
                    dockClickDetector.clickedIcon = nil // 清除，避免重复检测

                    print("🖱️ AppState: 检测到 Dock 点击 '\(clickedIcon.title)'")

                    // 处理点击
                    await handleDockClick(for: clickedIcon)

                    // 处理完成
                    isProcessing = false
                }
            }
        }
    }

    private func handleDockClick(for icon: DockIconInfo) async {
        // 🔧 关键修复：立即记录点击前的前台应用，避免被 macOS Dock 自动激活影响判断
        let frontmostAppBeforeClick = NSWorkspace.shared.frontmostApplication
        let frontmostPIDBeforeClick = frontmostAppBeforeClick?.processIdentifier ?? -1

        print("📸 AppState: 点击前前台应用 PID=\(frontmostPIDBeforeClick)")

        // 🔧 修复：更新最后点击时间，防止点击后立即显示预览
        lastClickTime = Date()

        // 🔧 修复问题2：点击时立即隐藏预览，避免显示最小化动画
        dockPreviewPanel.hide()

        // 🔧 修复：点击后暂停悬停检测，避免鼠标不动时立即显示预览
        dockHoverDetector.pauseHoverDetection()

        // 获取该应用的所有窗口
        do {
            let allWindows = try await windowEngine.activeWindows()

            // 根据 bundleID 或 appName 过滤窗口
            let appWindows = allWindows.filter { window in
                // 尝试通过 URL 获取 bundleID
                if let url = icon.url,
                   let bundle = Bundle(url: url),
                   let bundleID = bundle.bundleIdentifier {
                    return window.bundleIdentifier == bundleID
                }

                // 降级：通过应用名称匹配
                return window.appName == icon.title
            }

            print("🎯 AppState: 处理 '\(icon.title)' 的点击，窗口数量: \(appWindows.count)")

            // 🔧 关键修复：传递点击前的前台应用 PID
            await dockWindowController.handleDockClick(
                for: icon,
                windows: appWindows,
                frontmostPIDBeforeClick: frontmostPIDBeforeClick
            )

            // 🔧 修复：不再自动刷新预览，让鼠标移动后自然触发
            // 用户需要移动鼠标才会重新显示预览，避免点击后立即弹出

        } catch {
            print("⚠️ AppState: 处理 Dock 点击失败 - \(error)")
        }
    }

    // MARK: - Existing Methods
    
    private func startMonitoringWindows() async {
        for await windows in windowManager.windowsStream() {
            self.runningWindows = windows
        }
    }
    
    private func startMonitoringPurchases() async {
        for await status in storeService.proStatusStream() {
            self.isPro = status
        }
    }
    
    func toggleSwitcher() {
        // 1. 权限检查
        guard WindowEngine.checkAccessibilityPermission() else {
            let alert = NSAlert()
            // 修改点：使用 String(localized:) 显式进行本地化
            alert.messageText = String(localized: "Permissions Missing")
            alert.informativeText = String(localized: "DockSens needs Accessibility permissions.")
            alert.addButton(withTitle: String(localized: "Open Settings"))
            alert.addButton(withTitle: String(localized: "Cancel"))
            
            if alert.runModal() == .alertFirstButtonReturn {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
            return
        }

        // 2. 切换逻辑
        guard !isSwitcherVisible else { 
            // 如果当前已经是显示状态，则触发隐藏
            print("AppState: Toggle -> Hide")
            windowManager.hideSwitcher()
            // 注意：这里不需要手动设为 false，因为 hideSwitcher 会触发下面的 onWindowClose 回调
            return
        }
        
        print("AppState: Toggle -> Show")
        // 手动设为 true，防止重复触发
        isSwitcherVisible = true
        
        // 3. 显示并监听关闭
        windowManager.showSwitcher { [weak self] in
            Task { @MainActor in
                print("AppState: Switcher Closed (Callback Received)")
                self?.isSwitcherVisible = false
            }
        }
    }
    
    // MARK: - Window Snapping

    func snapActiveWindow(to position: SnapPosition) {
        // 同步调用，不使用 Task，避免并发问题
        windowSnapper.snapActiveWindow(to: position)
    }
}