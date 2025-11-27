//
//  WindowInfo.swift
//  DockSens
//
//  Created by DockSens Team.
//

import Foundation
import CoreGraphics

struct WindowInfo: Identifiable, @unchecked Sendable {
    // ⚡️ UI 唯一标识 (每次生成，解决渲染冲突)
    let id: UUID
    // ⚡️ 系统标识 (可能为 0，用于排序参考)
    let windowID: UInt32
    
    let pid: pid_t
    let title: String
    let appName: String
    let bundleIdentifier: String
    let frame: CGRect
    let image: CGImage?
    let isMinimized: Bool
    
    // ⚡️ 缓存的 AXUIElement，用于 O(1) 操作
    // Use wrapper to ensure Sendable and avoid MainActor inference
    let axElement: AXElementWrapper?
}

struct AXElementWrapper: @unchecked Sendable {
    private nonisolated let box: AXElementBox
    
    init(_ value: AnyObject) {
        self.box = AXElementBox(value)
    }
    
    nonisolated var value: AnyObject {
        if let p = UnsafeMutableRawPointer(bitPattern: box.addr) {
            return Unmanaged<AnyObject>.fromOpaque(p).takeUnretainedValue()
        }
        fatalError("Invalid pointer address")
    }
}

private final class AXElementBox: @unchecked Sendable {
    nonisolated let addr: UInt
    
    init(_ val: AnyObject) {
        let p = Unmanaged.passRetained(val).toOpaque()
        addr = UInt(bitPattern: p)
    }
    
    deinit {
        if let p = UnsafeMutableRawPointer(bitPattern: addr) {
            Unmanaged<AnyObject>.fromOpaque(p).release()
        }
    }
}

struct DockIconInfo: Identifiable, Sendable {
    let id: Int
    let title: String
    let frame: CGRect
    let url: URL?
}
