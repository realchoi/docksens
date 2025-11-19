//
//  Permissions.swift
//  DockSens
//
//  Created by DockSens Setup Script.
//

import AppKit

// TODO: 权限检查工具。
// ---------------------------------------------------------

enum Permissions { static func isAccessibilityTrusted() -> Bool { AXIsProcessTrusted() } }
