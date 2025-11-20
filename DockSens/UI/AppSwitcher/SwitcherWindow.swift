//
//  SwitcherWindow.swift
//  DockSens
//
//  Created by DockSens Team.
//

import SwiftUI
import AppKit
import ApplicationServices

// MARK: - SwiftUI View (保持不变)

struct SwitcherView: View {
    @ObservedObject var viewModel: SwitcherViewModel
    
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
                            .scaleEffect(index == viewModel.selectedIndex ? 1.05 : 1.0)
                            .offset(y: index == viewModel.selectedIndex ? -4 : 0)
                            .animation(.snappy(duration: 0.2), value: viewModel.selectedIndex)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(30)
                .background(.thinMaterial)
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
    }
}

struct WindowItemView: View {
    let window: WindowInfo
    let isSelected: Bool
    
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.white.opacity(0.1))
                
                if let cgImage = window.image {
                    Image(decorative: cgImage, scale: 1.0)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(8)
                        .shadow(color: .black.opacity(0.3), radius: isSelected ? 6 : 2, x: 0, y: 4)
                } else {
                    Image(systemName: "macwindow")
                        .font(.system(size: 48))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .opacity(0.5)
                }
                
                if let firstChar = window.appName.first {
                    Text(String(firstChar))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 24, height: 24)
                        .background(Color.white)
                        .clipShape(Circle())
                        .shadow(radius: 2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding([.bottom, .trailing], -8)
                }
            }
            .frame(width: 180, height: 120)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accentColor : Color.white.opacity(0.1), lineWidth: isSelected ? 2 : 1)
            )
            
            VStack(spacing: 2) {
                Text(window.appName)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .medium)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                
                if !window.title.isEmpty && window.title != window.appName {
                    Text(window.title)
                        .font(.caption2)
                        .foregroundStyle(.secondary.opacity(0.8))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(width: 180)
            .lineLimit(1)
        }
        .opacity(isSelected ? 1.0 : 0.8)
    }
}

// MARK: - Panel Controller

@MainActor
class SwitcherPanelController {
    private var panel: NSPanel?
    private let viewModel = SwitcherViewModel()
    var onClose: (() -> Void)?
    
    init() {}
    
    private func createPanel() -> NSPanel {
        guard let screen = NSScreen.main else { return NSPanel() }
        let newPanel = NSPanel(
            contentRect: screen.frame,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        // Agent App 使用 .modalPanel 可以确保覆盖在大多数窗口之上
        newPanel.level = .modalPanel
        newPanel.backgroundColor = .clear
        newPanel.isOpaque = false
        newPanel.hasShadow = false
        newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return newPanel
    }
    
    func show(windows: [WindowInfo]) {
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
            
            // ⚡️ Agent App 激活流程：
            Task {
                await self.activateWindowSafely(selectedWindow)
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
    
    // MARK: - Activation Strategy
    
    private func activateWindowSafely(_ window: WindowInfo) async {
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.processIdentifier == window.pid }) else {
            return
        }
        
        print("🚀 Agent Activating: \(window.appName)")
        
        // 1. 确保 App 不是隐藏状态 (Agent 必须显式调用 unhide)
        app.unhide()
        
        // 2. 暴力激活
        // Bit 0: activateIgnoringOtherApps (1 << 0)
        // Bit 1: activateAllWindows (1 << 1)
        let rawOptions: UInt = (1 << 0) | (1 << 1)
        let options = NSApplication.ActivationOptions(rawValue: rawOptions)
        
        // Agent 拥有特权，调用此方法通常能成功抢占
        app.activate(options: options)
        
        // 3. 等待 WindowServer 处理
        try? await Task.sleep(for: .milliseconds(50))
        
        // 4. AX 提升具体窗口
        await performAXRaise(window)
    }
    
    private func performAXRaise(_ window: WindowInfo) async {
        let pid = window.pid
        let title = window.title
        
        await Task.detached {
            let appRef = AXUIElementCreateApplication(pid)
            var windowsRef: CFTypeRef?
            
            guard AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                  let windowList = windowsRef as? [AXUIElement] else {
                return
            }
            
            let match = windowList.first { axWindow in
                var titleRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef) == .success,
                   let t = titleRef as? String {
                    return t == title
                }
                return false
            }
            
            if let targetWindow = match ?? windowList.first {
                // A. Raise
                AXUIElementPerformAction(targetWindow, kAXRaiseAction as CFString)
                // B. Main
                AXUIElementSetAttributeValue(targetWindow, kAXMainAttribute as CFString, true as CFTypeRef)
                // C. Focused
                AXUIElementSetAttributeValue(targetWindow, kAXFocusedAttribute as CFString, true as CFTypeRef)
            }
        }.value
    }
}