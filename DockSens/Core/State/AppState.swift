//
//  AppState.swift
//  DockSens
//
//  Created by DockSens Team.
//

import SwiftUI
import Observation
import Combine

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
    private let dockMonitor = DockMonitor() // 🔧 新增：Dock 监控器
    private let dockHoverDetector: DockHoverDetector
    private let dockPreviewPanel = DockPreviewPanelController()
    private let windowEngine = WindowEngine()

    // Dock 点击相关 (Stage 4)
    private let dockClickDetector: DockClickDetector
    // private let dockWindowController = DockWindowController() // 已移除

    // 🔧 添加：跟踪最后点击时间，防止点击后立即显示预览
    private var lastClickTime: Date = .distantPast

    init() {
        // 初始化 DockHoverDetector (不再需要 engine)
        self.dockHoverDetector = DockHoverDetector(dockMonitor: dockMonitor)
        // 初始化 DockClickDetector（需要传入 hoverDetector 和 dockMonitor）
        self.dockClickDetector = DockClickDetector(hoverDetector: dockHoverDetector, dockMonitor: dockMonitor)

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

    // MARK: - Dock Menu Detection (问题3修复)
    
    /// 检测 Dock 右键菜单是否存在
    private func isDockMenuVisible() -> Bool {
        // 检查 Dock 进程是否有菜单窗口显示
        let dockApps = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == "com.apple.dock"
        }
        guard let dockApp = dockApps.first else { return false }
        
        let dockRef = AXUIElementCreateApplication(dockApp.processIdentifier)
        
        // 检查是否有菜单栏或上下文菜单
        if let _ = AXUtils.getAXAttribute(dockRef, kAXMenuBarAttribute, ofType: AXUIElement.self) {
            // 有菜单栏，可能是右键菜单
            return true
        }
        
        // 检查是否有焦点元素（通常右键菜单会成为焦点）
        if let focused = AXUtils.getAXAttribute(dockRef, kAXFocusedUIElementAttribute, ofType: AXUIElement.self) {
            let role = AXUtils.getAXAttribute(focused, kAXRoleAttribute, ofType: String.self)
            if role == "AXMenu" || role == "AXMenuItem" {
                return true
            }
        }
        
        return false
    }

    // MARK: - Dock Preview Management

    private func startDockHoverMonitoring() {
        dockHoverDetector.startMonitoring()

        // 使用 Combine 监听悬浮状态，替代轮询
        dockHoverDetector.$hoveredIcon
            .removeDuplicates { $0?.id == $1?.id }
            .sink { [weak self] icon in
                guard let self = self else { return }
                
                // 1. 检查是否在点击冷却时间内
                let timeSinceClick = Date().timeIntervalSince(self.lastClickTime)
                if timeSinceClick < 0.5 {
                    return
                }
                
                // 2. 处理悬浮状态变化
                if let icon = icon {
                    // 🔧 修复问题3：检查是否有 Dock 右键菜单存在
                    if self.isDockMenuVisible() {
                        // 有右键菜单时，不显示预览
                        self.dockPreviewPanel.hide()
                        return
                    }

                    // 🔧 修复：检查 "Dock 预览" 开关设置
                    // 如果用户关闭了预览，直接隐藏并返回
                    let showPreviews = UserDefaults.standard.bool(forKey: "showDockPreviews")
                    if !showPreviews {
                        self.dockPreviewPanel.hide()
                        return
                    }
                    
                    // 🔧 修复问题2：取消延迟隐藏，直接显示
                    self.dockPreviewPanel.cancelScheduledHide()
                    
                    Task {
                        await self.showDockPreview(for: icon)
                    }
                } else {
                    // 🔧 修复问题4：离开 Dock 时延迟隐藏
                    self.dockPreviewPanel.scheduleHide(delay: 0.3)
                }
            }
            .store(in: &cancellables)
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

    private var cancellables = Set<AnyCancellable>()
    
    // 🔧 状态追踪：记录 MouseDown 时的意图
    private var pendingMinimizePID: pid_t? = nil

    private func startDockClickMonitoring() {
        dockClickDetector.startMonitoring()

        // 1. 监听 MouseDown：判断是否应该最小化
        dockClickDetector.$mouseDownIcon
            .compactMap { $0 }
            .sink { [weak self] icon in
                guard let self = self else { return }
                self.handleDockMouseDown(for: icon)
            }
            .store(in: &cancellables)
            
        // 2. 监听 MouseUp：执行操作
        dockClickDetector.$mouseUpIcon
            .compactMap { $0 }
            .sink { [weak self] icon in
                guard let self = self else { return }
                self.handleDockMouseUp(for: icon)
            }
            .store(in: &cancellables)
            
        // 监听右键点击
        dockClickDetector.$rightClickedIcon
            .compactMap { $0 }
            .sink { [weak self] _ in
                guard let self = self else { return }
                print("🖱️ AppState: 检测到右键点击，隐藏预览")
                self.dockPreviewPanel.hide()
                self.dockClickDetector.rightClickedIcon = nil
                self.dockHoverDetector.pauseHoverDetection()
            }
            .store(in: &cancellables)
    }
    
    private func handleDockMouseDown(for icon: DockIconInfo) {
        // 1. 查找对应的应用
        guard let app = findRunningApp(for: icon) else { return }
        
        // 2. 快速检查：应用是否前台且有可见窗口？
        // 如果是，说明用户意图可能是“最小化”。
        // 如果不是（应用后台或窗口最小化），用户意图是“激活/恢复”，这部分交给系统处理，我们不干预。
        
        Task {
            let shouldMinimize = await windowEngine.isAppFocusedAndVisible(pid: app.processIdentifier)
            
            await MainActor.run {
                if shouldMinimize {
                    print("🖱️ AppState: MouseDown 检测到活跃窗口，准备在 Up 时最小化 (PID: \(app.processIdentifier))")
                    self.pendingMinimizePID = app.processIdentifier
                } else {
                    self.pendingMinimizePID = nil
                }
                
                // 隐藏预览
                dockPreviewPanel.hide()
                dockHoverDetector.pauseHoverDetection()
            }
        }
    }

    private func handleDockMouseUp(for icon: DockIconInfo) {
        lastClickTime = Date()
        dockPreviewPanel.hide()
        dockHoverDetector.pauseHoverDetection()
        
        guard let app = findRunningApp(for: icon) else { return }
        
        // 检查是否匹配之前 MouseDown 的意图
        if let pendingPID = self.pendingMinimizePID, pendingPID == app.processIdentifier {
            print("🖱️ AppState: MouseUp 执行最小化 (PID: \(pendingPID))")
            
            // 执行最小化
            // 我们需要找到该应用的窗口并最小化它
            Task {
                // 获取窗口列表 (使用缓存)
                if let windows = try? await windowEngine.windows(for: app),
                   let targetWindow = windows.first(where: { !$0.isMinimized }) {
                    AXUtils.minimizeWindow(targetWindow)
                }
            }
            
            // 重置状态
            self.pendingMinimizePID = nil
        } else {
            // 意图不是最小化（或者 MouseDown 时判断为后台/最小化），
            // 此时系统 Dock 会自动处理“激活”或“恢复”，我们什么都不做。
            print("🖱️ AppState: MouseUp 忽略 (交由系统处理)")
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
        guard AXUtils.checkAccessibilityPermission() else {
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