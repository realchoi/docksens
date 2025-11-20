//
//  WindowSnapper.swift
//  DockSens
//
//  Created by DockSens Team.
//

import AppKit
import ApplicationServices
import Foundation

enum SnapPosition {
    case left
    case right
    case maximize
    case center
}

actor WindowSnapper {
    
    func snapActiveWindow(to position: SnapPosition) {
        // 1. 获取当前活跃窗口
        guard let focusedWindow = getFocusedWindow() else {
            print("WindowSnapper: No focused window found")
            return
        }
        
        // 2. 获取当前窗口所在的屏幕
        guard let currentFrame = getWindowFrame(focusedWindow),
              let screen = getScreen(containing: currentFrame) else {
            print("WindowSnapper: Could not determine screen for window")
            return
        }
        
        // 3. 坐标转换准备
        guard let primaryScreen = NSScreen.screens.first else { return }
        let primaryHeight = primaryScreen.frame.height
        let visibleFrameCocoa = screen.visibleFrame
        
        let axY = primaryHeight - (visibleFrameCocoa.origin.y + visibleFrameCocoa.height)
        let axVisibleFrame = CGRect(
            x: visibleFrameCocoa.origin.x,
            y: axY,
            width: visibleFrameCocoa.width,
            height: visibleFrameCocoa.height
        )
        
        // 4. 计算目标 Frame
        var targetFrame = axVisibleFrame
        
        switch position {
        case .left:
            targetFrame.size.width = axVisibleFrame.width / 2
        case .right:
            targetFrame.origin.x = axVisibleFrame.minX + axVisibleFrame.width / 2
            targetFrame.size.width = axVisibleFrame.width / 2
        case .maximize:
            break
        case .center:
            let width = axVisibleFrame.width * 0.8
            let height = axVisibleFrame.height * 0.8
            targetFrame = CGRect(
                x: axVisibleFrame.midX - width / 2,
                y: axVisibleFrame.midY - height / 2,
                width: width,
                height: height
            )
        }
        
        // 5. 执行动画
        animateWindow(focusedWindow, from: currentFrame, to: targetFrame)
    }
    
    // MARK: - Animation Logic
    
    private func animateWindow(_ window: AXUIElement, from startRect: CGRect, to endRect: CGRect) {
        let duration: TimeInterval = 0.2
        let steps = 12 // 60fps * 0.2s
        let stepDuration = duration / Double(steps)
        
        Task {
            for i in 1...steps {
                let progress = Double(i) / Double(steps)
                let easedProgress = easeOutQuad(progress)
                
                let newX = startRect.origin.x + (endRect.origin.x - startRect.origin.x) * easedProgress
                let newY = startRect.origin.y + (endRect.origin.y - startRect.origin.y) * easedProgress
                let newW = startRect.width + (endRect.width - startRect.width) * easedProgress
                let newH = startRect.height + (endRect.height - startRect.height) * easedProgress
                
                let intermediateRect = CGRect(x: newX, y: newY, width: newW, height: newH)
                
                // 使用 Robust 设置，但为了性能，中间帧可以只设置一次 Size/Pos
                // 最后一帧必须 Robust
                if i == steps {
                    setWindowFrameRobust(window, to: intermediateRect)
                } else {
                    setWindowFrameFast(window, to: intermediateRect)
                }
                
                try? await Task.sleep(for: .seconds(stepDuration))
            }
        }
    }
    
    private func easeOutQuad(_ t: Double) -> Double {
        return t * (2 - t)
    }
    
    // MARK: - Accessibility Helpers
    
    private func getFocusedWindow() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedApp: CFTypeRef?
        
        let result = AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &focusedApp)
        guard result == .success, let app = focusedApp else { return nil }
        
        var focusedWindow: CFTypeRef?
        let windowResult = AXUIElementCopyAttributeValue(app as! AXUIElement, kAXFocusedWindowAttribute as CFString, &focusedWindow)
        
        if windowResult == .success {
            return (focusedWindow as! AXUIElement)
        }
        return nil
    }
    
    private func getWindowFrame(_ window: AXUIElement) -> CGRect? {
        var posValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        
        AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posValue)
        AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue)
        
        guard let posRef = posValue, CFGetTypeID(posRef) == AXValueGetTypeID(),
              let sizeRef = sizeValue, CFGetTypeID(sizeRef) == AXValueGetTypeID() else { return nil }
        
        let pos = posRef as! AXValue
        let size = sizeRef as! AXValue
        
        var point = CGPoint.zero
        var rectSize = CGSize.zero
        
        AXValueGetValue(pos, .cgPoint, &point)
        AXValueGetValue(size, .cgSize, &rectSize)
        
        return CGRect(origin: point, size: rectSize)
    }
    
    private func setWindowFrameFast(_ window: AXUIElement, to rect: CGRect) {
        setSize(window, size: rect.size)
        setPosition(window, point: rect.origin)
    }
    
    private func setWindowFrameRobust(_ window: AXUIElement, to rect: CGRect) {
        setSize(window, size: rect.size)
        setPosition(window, point: rect.origin)
        setSize(window, size: rect.size)
    }
    
    private func setPosition(_ window: AXUIElement, point: CGPoint) {
        var pt = point
        if let posValue = AXValueCreate(.cgPoint, &pt) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)
        }
    }
    
    private func setSize(_ window: AXUIElement, size: CGSize) {
        var sz = size
        if let sizeValue = AXValueCreate(.cgSize, &sz) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        }
    }
    
    private func getScreen(containing rect: CGRect) -> NSScreen? {
        guard let primaryScreen = NSScreen.screens.first else { return NSScreen.main }
        let primaryHeight = primaryScreen.frame.height
        let cocoaY = primaryHeight - (rect.origin.y + rect.height)
        let cocoaCenter = CGPoint(x: rect.midX, y: cocoaY + rect.height / 2)
        return NSScreen.screens.first { $0.frame.contains(cocoaCenter) } ?? NSScreen.main
    }
}
