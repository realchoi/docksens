//
//  WindowActivator.swift
//  DockSens
//
//  Created by DockSens Team.
//

import AppKit
import ApplicationServices

/// 负责激活和还原窗口
final class WindowActivator {

    /// 激活指定的窗口（复用 SwitcherWindow 的逻辑）
    func activateWindow(_ window: WindowInfo) async {
        // 1. 激活应用程序
        guard let app = NSRunningApplication(processIdentifier: window.pid) else {
            print("⚠️ WindowActivator: 无法找到 PID \(window.pid) 对应的应用")
            return
        }

        // macOS 14+ API: 让出激活权
        if #available(macOS 14.0, *) {
            NSApp.yieldActivation(to: app)
        }

        // 激活应用（包含所有窗口，忽略其他应用）
        let rawOptions: UInt = (1 << 0) | (1 << 1)
        let options = NSApplication.ActivationOptions(rawValue: rawOptions)
        app.activate(options: options)

        // 等待激活生效
        try? await Task.sleep(for: .milliseconds(50))

        // 2. 使用 AX API 提升窗口
        // 使用 AXUtils 提升窗口
        await Task.detached {
            AXUtils.raiseWindow(window)
        }.value
    }
}
