//
//  SwitcherWindow.swift
//  DockSens
//
//  Created by DockSens Team.
//

import SwiftUI
import AppKit
import ApplicationServices
import UniformTypeIdentifiers

// MARK: - SwiftUI View

struct SwitcherView: View {
    @ObservedObject var viewModel: SwitcherViewModel
    @AppStorage("previewSize") private var previewSize: Double = 1.0
    
    private let baseWidth: CGFloat = 160
    private let baseHeight: CGFloat = 110
    private let gridSpacing: CGFloat = 20
    private let horizontalPadding: CGFloat = 25
    private let maxContainerWidth: CGFloat = 1100
    
    @State private var contentHeight: CGFloat = 300
    
    private var calculatedGridWidth: CGFloat {
        let count = viewModel.windows.count
        if count == 0 { return 300 }
        let itemWidth = baseWidth * previewSize
        let maxCols = Int((maxContainerWidth - (horizontalPadding * 2) + gridSpacing) / (itemWidth + gridSpacing))
        let actualCols = max(1, min(count, maxCols))
        return CGFloat(actualCols) * itemWidth + CGFloat(actualCols - 1) * gridSpacing + (horizontalPadding * 2)
    }
    
    var body: some View {
        ZStack {
            if viewModel.isVisible {
                VStack(spacing: 20) {
                    Text("Switch Window")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 15)
                    
                    GeometryReader { geometry in
                        let maxAllowedHeight = (NSScreen.main?.frame.height ?? 900) * 0.85
                        
                        ScrollView(.vertical, showsIndicators: true) {
                            LazyVGrid(
                                columns: [
                                    GridItem(.adaptive(minimum: baseWidth * previewSize, maximum: baseWidth * previewSize * 1.5), spacing: gridSpacing)
                                ],
                                spacing: gridSpacing
                            ) {
                                ForEach(Array(viewModel.windows.enumerated()), id: \.element.id) { index, window in
                                    WindowItemView(
                                        window: window,
                                        isSelected: index == viewModel.selectedIndex,
                                        scaleFactor: previewSize,
                                        baseSize: CGSize(width: baseWidth, height: baseHeight)
                                    )
                                    .onTapGesture {
                                        viewModel.selectedIndex = index
                                        viewModel.handleSelect()
                                    }
                                }
                            }
                            .padding(.horizontal, horizontalPadding)
                            .padding(.vertical, 25)
                            .background(
                                GeometryReader { geo -> Color in
                                    DispatchQueue.main.async {
                                        self.contentHeight = geo.size.height + 60
                                    }
                                    return Color.clear
                                }
                            )
                        }
                        .frame(height: min(contentHeight, maxAllowedHeight))
                    }
                    .frame(height: min(contentHeight, (NSScreen.main?.frame.height ?? 900) * 0.85))
                }
                .padding(.bottom, 10)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(.white.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.4), radius: 50, x: 0, y: 25)
                .frame(width: calculatedGridWidth)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct WindowItemView: View {
    let window: WindowInfo
    let isSelected: Bool
    let scaleFactor: Double
    let baseSize: CGSize
    
    private var itemWidth: CGFloat { baseSize.width * scaleFactor }
    private var itemHeight: CGFloat { baseSize.height * scaleFactor }
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.black.opacity(0.1))
                
                if let cgImage = window.image {
                    Image(decorative: cgImage, scale: 1.0)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(8)
                        .shadow(color: .black.opacity(0.3), radius: isSelected ? 5 : 2, x: 0, y: 3)
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "macwindow.on.rectangle")
                            .font(.system(size: 30 * scaleFactor))
                            .foregroundStyle(.secondary.opacity(0.3))
                        
                        if window.isMinimized {
                            Text("Minimized")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary.opacity(0.8))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.ultraThinMaterial)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
            .frame(width: itemWidth, height: itemHeight)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 3)
            )
            .overlay(alignment: .bottomTrailing) {
                AppIconView(bundleID: window.bundleIdentifier, pid: window.pid)
                    .frame(width: 32 * scaleFactor, height: 32 * scaleFactor)
                    .shadow(radius: 3)
                    .offset(x: -6, y: -6)
            }
            
            VStack(spacing: 2) {
                Text(window.appName)
                    .font(.system(size: 13 * scaleFactor, weight: isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                
                if !window.title.isEmpty && window.title != window.appName {
                    Text(window.title)
                        .font(.system(size: 11 * scaleFactor))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(width: itemWidth + 20)
            .lineLimit(1)
        }
        .scaleEffect(isSelected ? 1.03 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        .contentShape(Rectangle())
    }
}

struct AppIconView: View {
    let bundleID: String
    let pid: pid_t
    @State private var icon: NSImage?
    
    var body: some View {
        Group {
            if let nsImage = icon {
                Image(nsImage: nsImage)
                    .resizable()
            } else {
                Image(systemName: "app.fill")
                    .foregroundStyle(.gray)
            }
        }
        .onAppear {
            if icon == nil { self.icon = getAppIcon() }
        }
    }
    
    private func getAppIcon() -> NSImage {
        if !bundleID.isEmpty,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: appURL.path)
        }
        if let app = NSRunningApplication(processIdentifier: pid), let icon = app.icon {
            return icon
        }
        return NSWorkspace.shared.icon(for: .applicationBundle)
    }
}

// MARK: - Panel Controller

@MainActor
class SwitcherPanelController {
    private var panel: NSPanel?
    private let viewModel = SwitcherViewModel()
    var onClose: (() -> Void)?
    
    // 新增回调：当选择窗口时通知 Manager
    var onSelect: ((WindowInfo) -> Void)?
    
    init() {}
    
    private func createPanel() -> NSPanel {
        guard let screen = NSScreen.main else { return NSPanel() }
        let newPanel = NSPanel(
            contentRect: screen.frame,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        newPanel.level = .modalPanel
        newPanel.backgroundColor = .clear
        newPanel.isOpaque = false
        newPanel.hasShadow = false
        newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return newPanel
    }
    
    // ⚡️ 签名更新：接收 onSelect 回调
    func show(windows: [WindowInfo], onSelect: @escaping (WindowInfo) -> Void) {
        self.onSelect = onSelect
        
        let flags = CGEventSource.flagsState(.hidSystemState)
        let isOptionHeld = flags.contains(.maskAlternate)
        
        if !isOptionHeld {
            if windows.count > 1 {
                let targetIndex = 1
                if windows.indices.contains(targetIndex) {
                    let targetWindow = windows[targetIndex]
                    Task {
                        await self.activateWindowSafely(targetWindow)
                        self.onSelect?(targetWindow) // 通知更新 MRU
                        self.onClose?()
                    }
                    return
                }
            }
        }
        
        if panel != nil {
            panel?.orderOut(nil)
            panel = nil
        }
        panel = createPanel()
        guard let currentPanel = panel, let screen = NSScreen.main else { return }
        
        let rootView = SwitcherView(viewModel: viewModel)
        let hostingView = NSHostingView(rootView: rootView.ignoresSafeArea())
        
        hostingView.translatesAutoresizingMaskIntoConstraints = true
        hostingView.autoresizingMask = [.width, .height]
        hostingView.sizingOptions = []
        hostingView.frame = CGRect(origin: .zero, size: screen.frame.size)
        
        currentPanel.contentView = hostingView
        
        viewModel.show(with: windows) { [weak self] selectedWindow in
            guard let self = self else { return }
            Task {
                await self.activateWindowSafely(selectedWindow)
                self.onSelect?(selectedWindow) // 通知更新 MRU
                self.hide()
            }
        }
        
        currentPanel.orderFront(nil)
    }
    
    func hide() {
        guard panel != nil else { return }
        viewModel.hide()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.panel?.orderOut(nil)
            self.panel = nil
            self.onClose?()
        }
    }
    
    private func activateWindowSafely(_ window: WindowInfo) async {
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.processIdentifier == window.pid }) else { return }
        
        app.unhide()
        if #available(macOS 14.0, *) { NSApp.yieldActivation(to: app) }
        
        let rawOptions: UInt = (1 << 0) | (1 << 1)
        let options = NSApplication.ActivationOptions(rawValue: rawOptions)
        app.activate(options: options)
        
        try? await Task.sleep(for: .milliseconds(50))
        await performAXRaise(window)
    }
    
    private func performAXRaise(_ window: WindowInfo) async {
        let pid = window.pid
        let targetTitle = window.title
        let targetFrame = window.frame
        
        await Task.detached { [weak self] in
            guard let self = self else { return }
            
            let appRef = AXUIElementCreateApplication(pid)
            var windowsRef: CFTypeRef?
            
            guard self.getAXAttribute(appRef, kAXWindowsAttribute as String, ofType: [AXUIElement].self) != nil else { return }
            
            if AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef) != .success { return }
            guard let windowList = windowsRef as? [AXUIElement] else { return }
            
            let match = windowList.first { axWindow in
                var titleRef: CFTypeRef?
                // 1. 标题匹配
                if AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef) == .success,
                   let t = titleRef as? String, t == targetTitle {
                    
                    // 2. 尺寸位置匹配 (放宽容差到 100，解决 "hit-or-miss")
                    if let posValue = self.getAXAttribute(axWindow, kAXPositionAttribute as String, ofType: AXValue.self),
                       let sizeValue = self.getAXAttribute(axWindow, kAXSizeAttribute as String, ofType: AXValue.self) {
                        
                        var pos = CGPoint.zero
                        var size = CGSize.zero
                        AXValueGetValue(posValue, .cgPoint, &pos)
                        AXValueGetValue(sizeValue, .cgSize, &size)
                        
                        let axCenter = CGPoint(x: pos.x + size.width/2, y: pos.y + size.height/2)
                        let targetCenter = CGPoint(x: targetFrame.midX, y: targetFrame.midY)
                        let dist = hypot(axCenter.x - targetCenter.x, axCenter.y - targetCenter.y)
                        
                        // ⚡️ 优化：容差 100pt，确保即使 AX/SCK 坐标有偏差也能命中
                        if dist < 100 { return true }
                    } else {
                        // 无法获取 Frame，但标题一致，认为匹配
                        return true
                    }
                }
                return false
            }
            
            if let targetWindow = match ?? windowList.first {
                // 最小化还原
                var minimizedRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(targetWindow, kAXMinimizedAttribute as CFString, &minimizedRef) == .success,
                   let minimized = minimizedRef as? Bool, minimized == true {
                     AXUIElementSetAttributeValue(targetWindow, kAXMinimizedAttribute as CFString, false as CFTypeRef)
                }
                
                // 激活
                AXUIElementPerformAction(targetWindow, kAXRaiseAction as CFString)
                AXUIElementSetAttributeValue(targetWindow, kAXMainAttribute as CFString, true as CFTypeRef)
                AXUIElementSetAttributeValue(targetWindow, kAXFocusedAttribute as CFString, true as CFTypeRef)
            }
        }.value
    }
    
    nonisolated private func getAXAttribute<T>(_ element: AXUIElement, _ attribute: String, ofType type: T.Type) -> T? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        if result == .success, let value = value {
            if T.self == AXValue.self { return value as? T }
            if T.self == String.self { return value as? T }
            if T.self == [AXUIElement].self { return value as? T }
            if T.self == Bool.self { return value as? T }
            if T.self == URL.self { return value as? T }
            return value as? T
        }
        return nil
    }
}