//
//  KeyboardInputManager.swift
//  DockSens
//
//  Created by DockSens Team.
//

import AppKit
import CoreGraphics

protocol KeyboardInputDelegate: AnyObject {
    func handlenavigateLeft()
    func handleNavigateRight()
    func handleSelect() // 回车或释放修饰键时触发
    func handleCancel() // ESC 触发
}

/// 负责在 App 处于后台时拦截键盘事件
class KeyboardInputManager {
    weak var delegate: KeyboardInputDelegate?
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    
    /// 启动键盘监听
    /// - Returns: 是否启动成功 (失败通常是因为无权限)
    func startMonitoring() -> Bool {
        guard eventTap == nil else { return true }
        
        // 关注的事件掩码：键盘按下
        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        
        // 创建 Event Tap
        // .cghidEventTap: 在 HID 层面拦截，优先级较高
        // .headInsertEventTap: 插入到队列头部
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                // 将 UnsafeRawPointer 转回实例
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<KeyboardInputManager>.fromOpaque(refcon).takeUnretainedValue()
                return manager.handleCGEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("❌ 无法创建 Event Tap，请检查辅助功能权限")
            return false
        }
        
        eventTap = tap
        
        // 添加到 RunLoop
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        
        // FIX: 补充缺失的 'tap' 参数
        CGEvent.tapEnable(tap: tap, enable: true)
        
        return true
    }
    
    func stopMonitoring() {
        guard let tap = eventTap, let source = runLoopSource else { return }
        
        // FIX: 补充缺失的 'tap' 参数
        CGEvent.tapEnable(tap: tap, enable: false)
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        
        // 释放资源 (Swift ARC 会处理 CF 对象，但 CFMachPort 需要显式 invalidate)
        CFMachPortInvalidate(tap)
        
        eventTap = nil
        runLoopSource = nil
    }
    
    // MARK: - Event Handler
    
    private func handleCGEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // 如果没有 delegate，不拦截任何事件
        guard let delegate = delegate else { return Unmanaged.passUnretained(event) }
        
        if type == .keyDown {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            
            // 键码映射 (ANSI 标准)
            // 123: Left, 124: Right, 53: Esc, 36: Enter
            switch keyCode {
            case 123: // Left Arrow
                delegate.handlenavigateLeft()
                return nil // 返回 nil 表示拦截该事件，不传递给当前 App
            case 124: // Right Arrow
                delegate.handleNavigateRight()
                return nil
            case 53: // ESC
                delegate.handleCancel()
                return nil
            case 36: // Enter
                delegate.handleSelect()
                return nil
            default:
                break
            }
        }
        
        // TODO: 处理 flagsChanged 以支持 Alt 键释放时确认选择 (经典 Alt-Tab 行为)
        
        return Unmanaged.passUnretained(event)
    }
}