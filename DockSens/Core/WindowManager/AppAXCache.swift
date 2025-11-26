//
//  AppAXCache.swift
//  DockSens
//
//  Created by DockSens Team.
//

import AppKit
import ApplicationServices

// ⚡️ 线程安全的 App AX 对象缓存
final class AppAXCache: @unchecked Sendable {
    private var cache: [pid_t: AXUIElement] = [:]
    private let lock = NSLock()
    
    init() {}
    
    func getElement(for pid: pid_t) -> AXUIElement {
        lock.lock()
        defer { lock.unlock() }
        
        if let element = cache[pid] {
            return element
        }
        
        let element = AXUIElementCreateApplication(pid)
        cache[pid] = element
        return element
    }
    
    func clear() {
        lock.lock()
        defer { lock.unlock() }
        cache.removeAll()
    }
}
