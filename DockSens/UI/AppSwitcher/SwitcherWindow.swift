//
//  SwitcherWindow.swift
//  DockSens
//
//  Created by DockSens Team.
//

import SwiftUI
import AppKit
import ApplicationServices

// MARK: - SwiftUI View

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
        newPanel.level = .modalPanel // 确保在最上层
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
            print("🎯 Selection Confirmed: \(selectedWindow.appName)")
            
            // ⚡️ 关键修复：
            // 不要立即 hide()！否则焦点会瞬间回到上一个窗口（Window A），
            // 导致我们接下来的激活操作（Activate B）被系统视为后台干扰。
            // 我们先执行激活，等 B 准备好了，再撤掉 DockSens。
            
            Task {
                await self?.performSequencedActivation(for: selectedWindow)
                // 激活流程走完后，再隐藏面板，这样用户看到的就是 B 了
                self?.hide()
            }
        }
        
        currentPanel.orderFront(nil)
    }
    
    func hide() {
        guard panel != nil else { return }
        viewModel.hide()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.panel?.orderOut(nil)
            self.panel = nil
            self.onClose?()
        }
    }
    
    // MARK: - Precision Activation Strategy
    
    private func performSequencedActivation(for window: WindowInfo) async {
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.processIdentifier == window.pid }) else {
            return
        }
        
        print("🚀 Step 1: Activate App \(window.appName)")
        app.unhide()
        app.activate(options: .activateAllWindows)
        
        // 稍微等待 App 响应激活指令
        try? await Task.sleep(for: .milliseconds(50))
        
        print("🚀 Step 2: AX Raise Specific Window")
        // 等待 AX 操作完成
        await activateViaAX(window)
    }
    
    private func activateViaAX(_ window: WindowInfo) async {
        let pid = window.pid
        let targetTitle = window.title
        
        // FIX: 使用 await ... .value 来等待 Task 执行完毕
        await Task.detached {
            let appRef = AXUIElementCreateApplication(pid)
            var windowsRef: CFTypeRef?
            
            guard AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                  let windowList = windowsRef as? [AXUIElement] else {
                return
            }
            
            // 精准匹配
            var match: AXUIElement?
            for axWindow in windowList {
                var titleRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef) == .success,
                   let titleStr = titleRef as? String, titleStr == targetTitle {
                    match = axWindow
                    break
                }
            }
            
            let target = match ?? windowList.first
            
            if let finalWindow = target {
                // 1. 提升层级 (Raise)
                AXUIElementPerformAction(finalWindow, kAXRaiseAction as CFString)
                
                // 2. FIX: 修正 API 名称，设置为“主窗口” (Main)
                AXUIElementSetAttributeValue(finalWindow, kAXMainAttribute as CFString, true as CFTypeRef)
                
                // 3. 尝试设置为“焦点窗口” (Focused) - 双重保险
                AXUIElementSetAttributeValue(finalWindow, kAXFocusedAttribute as CFString, true as CFTypeRef)
                
                print("✅ AX Action Performed (Raise + Main + Focused)")
            }
        }.value
    }
}