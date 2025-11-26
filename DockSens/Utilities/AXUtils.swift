//
//  AXUtils.swift
//  DockSens
//
//  Created by DockSens Team.
//

import AppKit
import ApplicationServices

/// Utility class for Accessibility API operations
enum AXUtils {
    
    // MARK: - Attribute Getting
    
    /// Generic method to get an AX attribute value
    nonisolated static func getAXAttribute<T>(_ element: AXUIElement, _ attribute: String, ofType type: T.Type) -> T? {
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
    
    // MARK: - Permissions
    
    /// Check if the app has accessibility permissions
    nonisolated static func checkAccessibilityPermission() -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
    
    // MARK: - Window Operations
    
    /// Raise a window to the front using AX API
    /// - Parameters:
    ///   - window: The window info to raise
    ///   - tolerance: Distance tolerance for matching window position (default 100)
    nonisolated static func raiseWindow(_ window: WindowInfo, tolerance: Double = 100.0) {
        let pid = window.pid
        let targetTitle = window.title
        let targetFrame = window.frame
        
        let appRef = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        
        // Get all windows for the app
        guard AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef) == .success else {
            print("⚠️ AXUtils: Failed to get windows for PID \(pid)")
            return
        }
        
        guard let windowList = windowsRef as? [AXUIElement] else {
            print("⚠️ AXUtils: Failed to cast window list")
            return
        }
        
        // Match target window
        let match = windowList.first { axWindow in
            var titleRef: CFTypeRef?
            
            // 1. Title match
            if AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef) == .success,
               let t = titleRef as? String, t == targetTitle {
                
                // 2. Position/Size match
                if let posValue = getAXAttribute(axWindow, kAXPositionAttribute as String, ofType: AXValue.self),
                   let sizeValue = getAXAttribute(axWindow, kAXSizeAttribute as String, ofType: AXValue.self) {
                    
                    var pos = CGPoint.zero
                    var size = CGSize.zero
                    AXValueGetValue(posValue, .cgPoint, &pos)
                    AXValueGetValue(sizeValue, .cgSize, &size)
                    
                    let axCenter = CGPoint(x: pos.x + size.width / 2, y: pos.y + size.height / 2)
                    let targetCenter = CGPoint(x: targetFrame.midX, y: targetFrame.midY)
                    let dist = hypot(axCenter.x - targetCenter.x, axCenter.y - targetCenter.y)
                    
                    if dist < tolerance { return true }
                } else {
                    // Fallback: Title matches, assume it's the one
                    return true
                }
            }
            return false
        }
        
        if let targetWindow = match ?? windowList.first {
            // Restore if minimized
            var minimizedRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(targetWindow, kAXMinimizedAttribute as CFString, &minimizedRef) == .success,
               let minimized = minimizedRef as? Bool, minimized == true {
                AXUIElementSetAttributeValue(targetWindow, kAXMinimizedAttribute as CFString, false as CFTypeRef)
                print("✅ AXUtils: Restored minimized window '\(targetTitle)'")
            }
            
            // Raise and Focus
            AXUIElementPerformAction(targetWindow, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(targetWindow, kAXMainAttribute as CFString, true as CFTypeRef)
            AXUIElementSetAttributeValue(targetWindow, kAXFocusedAttribute as CFString, true as CFTypeRef)
            
            print("✅ AXUtils: Raised window '\(targetTitle)'")
        } else {
            print("⚠️ AXUtils: Target window '\(targetTitle)' not found")
        }
    }
    
    /// Minimize a window using AX API
    nonisolated static func minimizeWindow(_ window: WindowInfo, tolerance: Double = 100.0) {
        let pid = window.pid
        let targetTitle = window.title
        let targetFrame = window.frame
        
        let appRef = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        
        guard AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef) == .success else {
            print("⚠️ AXUtils: Failed to get windows for PID \(pid)")
            return
        }
        
        guard let windowList = windowsRef as? [AXUIElement] else { return }
        
        let match = windowList.first { axWindow in
            var titleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef) == .success,
               let t = titleRef as? String, t == targetTitle {
                
                if let posValue = getAXAttribute(axWindow, kAXPositionAttribute as String, ofType: AXValue.self),
                   let sizeValue = getAXAttribute(axWindow, kAXSizeAttribute as String, ofType: AXValue.self) {
                    
                    var pos = CGPoint.zero
                    var size = CGSize.zero
                    AXValueGetValue(posValue, .cgPoint, &pos)
                    AXValueGetValue(sizeValue, .cgSize, &size)
                    
                    let axCenter = CGPoint(x: pos.x + size.width / 2, y: pos.y + size.height / 2)
                    let targetCenter = CGPoint(x: targetFrame.midX, y: targetFrame.midY)
                    let dist = hypot(axCenter.x - targetCenter.x, axCenter.y - targetCenter.y)
                    
                    if dist < tolerance { return true }
                } else {
                    return true
                }
            }
            return false
        }
        
        if let targetWindow = match ?? windowList.first {
            let result = AXUIElementSetAttributeValue(targetWindow, kAXMinimizedAttribute as CFString, true as CFTypeRef)
            if result == .success {
                print("✅ AXUtils: Minimized window '\(targetTitle)'")
            } else {
                print("⚠️ AXUtils: Failed to minimize window, error: \(result.rawValue)")
            }
        }
    }
    
    // MARK: - Dock Operations
    
    /// Extract Dock icon info from an AXUIElement
    nonisolated static func extractDockIconInfo(_ element: AXUIElement) -> DockIconInfo? {
        let title = getAXAttribute(element, kAXTitleAttribute, ofType: String.self) ?? "Unknown"
        let role = getAXAttribute(element, kAXRoleAttribute, ofType: String.self)
        if role != "AXDockItem" { return nil }
        
        var frame = CGRect.zero
        if let posValue = getAXAttribute(element, kAXPositionAttribute, ofType: AXValue.self),
           let sizeValue = getAXAttribute(element, kAXSizeAttribute, ofType: AXValue.self) {
            var pos = CGPoint.zero
            var size = CGSize.zero
            AXValueGetValue(posValue, .cgPoint, &pos)
            AXValueGetValue(sizeValue, .cgSize, &size)
            frame = CGRect(origin: pos, size: size)
        }
        
        var url: URL? = nil
        if let urlString = getAXAttribute(element, kAXURLAttribute, ofType: String.self) {
            url = URL(string: urlString)
        } else if let urlRef = getAXAttribute(element, kAXURLAttribute, ofType: URL.self) {
            url = urlRef
        }
        
        return DockIconInfo(id: Int(frame.origin.x), title: title, frame: frame, url: url)
    }
}
