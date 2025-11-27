//
//  WindowActivator.swift
//  DockSens
//
//  Created by DockSens Team.
//

import AppKit
import ApplicationServices
import CoreServices

// Bypass Swift availability check for GetProcessForPID
@_silgen_name("GetProcessForPID")
func GetProcessForPID(_ pid: pid_t, _ psn: inout ProcessSerialNumber) -> OSStatus

/// 负责激活和还原窗口
final class WindowActivator {

    /// 激活指定的窗口（复用 SwitcherWindow 的逻辑）
    func activateWindow(_ window: WindowInfo) async {
        // 1. 激活应用程序
        guard let app = NSRunningApplication(processIdentifier: window.pid) else {
            print("⚠️ WindowActivator: 无法找到 PID \(window.pid) 对应的应用")
            return
        }

        // 尝试使用私有 API 强制激活窗口
        var psn = ProcessSerialNumber()
        let status = GetProcessForPID(window.pid, &psn)
        
        if status == noErr {
            // 动态加载 _SLPSSetFrontProcessWithOptions 以避免链接错误
            let funcName = "_SLPSSetFrontProcessWithOptions"
            if let handle = dlopen(nil, RTLD_LAZY),
               let sym = dlsym(handle, funcName) {
                typealias FunctionType = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UInt32, UInt32) -> CGError
                let function = unsafeBitCast(sym, to: FunctionType.self)
                
                // 0x2 = kCPSUserGenerated (from DockDoor/AltTab)
                let result = function(&psn, window.windowID, 0x2)
                
                if result == .success {
                    // 如果成功，我们还需要确保窗口被提升
                    // 等待一小会儿让系统处理焦点切换
                    try? await Task.sleep(for: .milliseconds(20))
                    
                    await Task.detached {
                        AXUtils.raiseWindow(window)
                    }.value
                    return
                } else {
                    print("⚠️ WindowActivator: _SLPSSetFrontProcessWithOptions failed: \(result)")
                }
            }
        }

        // Fallback: 标准激活方式

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
