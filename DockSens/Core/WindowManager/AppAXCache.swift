//
//  AppAXCache.swift
//  DockSens
//
//  Created by DockSens Team.
//

import Foundation
import ApplicationServices

// ⚡️ Wrapper to make AXUIElement Sendable
// Removed: using AnyObject directly to avoid MainActor inference

// Private API to get CGWindowID from AXUIElement
@_silgen_name("_AXUIElementGetWindow")
nonisolated func _AXUIElementGetWindow(_ element: AnyObject, _ windowID: inout UInt32) -> AXError

// ⚡️ 线程安全的 App AX 对象缓存 (Actor)
actor SafeAppAXCache {
    // Store as AnyObject to avoid MainActor inference
    private var cache: [pid_t: AnyObject] = [:]
    
    init() {}
    
    func getElement(for pid: pid_t) -> AnyObject {
        if let element = cache[pid] {
            return element
        }
        
        let element = AXUIElementCreateApplication(pid)
        let storage = element as AnyObject
        cache[pid] = storage
        return storage
    }
    
    func clear() {
        cache.removeAll()
    }
}
