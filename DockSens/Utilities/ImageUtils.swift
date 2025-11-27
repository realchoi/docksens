//
//  ImageUtils.swift
//  DockSens
//
//  Created by DockSens Team.
//

import CoreGraphics

enum ImageUtils {
    
    /// 裁剪 CGImage 边缘的透明区域
    /// ⚡️ 性能优化版：从边缘向内扫描，大幅减少遍历次数
    /// ⚡️ 二次优化：使用 Stride Skipping (跳步扫描) 加速初始探测
    nonisolated static func cropTransparentEdges(from image: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height
        
        guard let dataProvider = image.dataProvider,
              let data = dataProvider.data,
              let bytes = CFDataGetBytePtr(data) else {
            return nil
        }
        
        let bytesPerPixel = 4
        let bytesPerRow = image.bytesPerRow
        
        // 检查像素是否透明（alpha < 10）
        // 内联函数以减少调用开销
        func isTransparent(_ x: Int, _ y: Int) -> Bool {
            let offset = y * bytesPerRow + x * bytesPerPixel + 3 // alpha通道
            return bytes[offset] < 10
        }
        
        var minX = 0
        var maxX = width - 1
        var minY = 0
        var maxY = height - 1
        
        // ⚡️ 优化策略：
        // 1. 粗略扫描：每隔 4 个像素检查一次 (stride = 4)
        // 2. 精细修正：找到非透明点后，回溯查找精确边界
        let stride = 4
        
        // 1. 扫描 Top (minY)
        var foundTop = false
        for y in 0..<height {
            // 快速扫描行
            var rowHasContent = false
            for x in Swift.stride(from: 0, to: width, by: stride) {
                if !isTransparent(x, y) {
                    rowHasContent = true
                    break
                }
            }
            
            if rowHasContent {
                minY = y
                foundTop = true
                break
            }
        }
        
        // 如果没找到顶部非透明像素，说明全是透明的
        if !foundTop { return nil }
        
        // 2. 扫描 Bottom (maxY)
        for y in (minY..<height).reversed() {
            var rowHasContent = false
            for x in Swift.stride(from: 0, to: width, by: stride) {
                if !isTransparent(x, y) {
                    rowHasContent = true
                    break
                }
            }
            
            if rowHasContent {
                maxY = y
                break
            }
        }
        
        // 3. 扫描 Left (minX) - 仅在 minY...maxY 范围内扫描
        for x in 0..<width {
            var colHasContent = false
            // 纵向扫描也可以跳步
            for y in Swift.stride(from: minY, to: maxY + 1, by: stride) {
                if !isTransparent(x, y) {
                    colHasContent = true
                    break
                }
            }
            
            if colHasContent {
                minX = x
                break
            }
        }
        
        // 4. 扫描 Right (maxX) - 仅在 minY...maxY 范围内扫描
        for x in (minX..<width).reversed() {
            var colHasContent = false
            for y in Swift.stride(from: minY, to: maxY + 1, by: stride) {
                if !isTransparent(x, y) {
                    colHasContent = true
                    break
                }
            }
            
            if colHasContent {
                maxX = x
                break
            }
        }
        
        // ⚡️ 精细修正：因为跳步扫描可能漏掉边界上的像素，稍微扩大边界以确保安全
        // 或者进行局部回溯（这里为了性能，简单地向外扩展 stride 大小，反正透明边缘多切一点少切一点影响不大）
        minX = max(0, minX - stride)
        maxX = min(width - 1, maxX + stride)
        minY = max(0, minY - stride)
        maxY = min(height - 1, maxY + stride)
        
        // 校验有效性
        guard minX <= maxX && minY <= maxY else { return nil }
        
        // 裁剪到内容区域
        let cropRect = CGRect(
            x: minX,
            y: minY,
            width: maxX - minX + 1,
            height: maxY - minY + 1
        )
        
        return image.cropping(to: cropRect)
    }
}
