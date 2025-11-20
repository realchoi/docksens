//
//  KeyboardInputManager.swift
//  DockSens
//
//  Created by DockSens Team.
//

import AppKit
import CoreGraphics

protocol KeyboardInputDelegate: AnyObject {
    func handleNavigateLeft()
    func handleNavigateRight()
    func handleSelect() // 回车或松开 Option 时触发
    func handleCancel() // ESC 触发
}

/// 负责在 App 处于后台时拦截键盘事件
class KeyboardInputManager {
    weak var delegate: KeyboardInputDelegate?
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    
    // 记录 Option 键状态
    private var isOptionPressed: Bool = false
    
    /// 启动键盘监听
    func startMonitoring() -> Bool {
        guard eventTap == nil else { return true }
        
        // 1. 关键修复：启动时立即获取当前修饰键状态
        // 否则如果用户已经按住 Option 进来的，我们无法检测到后续的“松开”事件
        let currentFlags = CGEventSource.flagsState(.hidSystemState)
        isOptionPressed = currentFlags.contains(.maskAlternate)
        
        // 关注的事件掩码：键盘按下 + 修饰键变化
        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<KeyboardInputManager>.fromOpaque(refcon).takeUnretainedValue()
                return manager.handleCGEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("❌ KeyboardInputManager: 无法创建 Event Tap")
            return false
        }
        
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        
        return true
    }
    
    func stopMonitoring() {
        guard let tap = eventTap, let source = runLoopSource else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        CFMachPortInvalidate(tap)
        
        eventTap = nil
        runLoopSource = nil
        isOptionPressed = false
    }
    
    // MARK: - Event Handler
    
    private func handleCGEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard let delegate = delegate else { return Unmanaged.passUnretained(event) }
        
        // 1. 处理修饰键 (Option 释放)
        if type == .flagsChanged {
            let flags = event.flags
            let newOptionPressed = flags.contains(.maskAlternate)
            
            // 只有当状态从 "按下" 变为 "没按下" 时，才触发选择
            if isOptionPressed && !newOptionPressed {
                print("⌨️ Option Released -> Selecting")
                DispatchQueue.main.async {
                    delegate.handleSelect()
                }
            }
            isOptionPressed = newOptionPressed
            
            return Unmanaged.passUnretained(event)
        }
        
        // 2. 处理按键按下
        if type == .keyDown {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let flags = event.flags
            let isShift = flags.contains(.maskShift)
            
            switch keyCode {
            case 123: // Left Arrow
                DispatchQueue.main.async { delegate.handleNavigateLeft() }
                return nil
            case 124: // Right Arrow
                DispatchQueue.main.async { delegate.handleNavigateRight() }
                return nil
            case 48: // Tab
                DispatchQueue.main.async {
                    if isShift { delegate.handleNavigateLeft() }
                    else { delegate.handleNavigateRight() }
                }
                return nil
            case 53: // ESC
                DispatchQueue.main.async { delegate.handleCancel() }
                return nil
            case 36: // Enter
                DispatchQueue.main.async { delegate.handleSelect() }
                return nil
            default:
                break
            }
        }
        
        return Unmanaged.passUnretained(event)
    }
}