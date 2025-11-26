//
//  WindowImageCache.swift
//  DockSens
//
//  Created by DockSens Team.
//

import Foundation
import CoreGraphics

/// 窗口截图缓存系统
/// 使用 Actor 确保线程安全的缓存访问
actor WindowImageCache {
    
    // MARK: - Cache Entry
    
    private struct CachedImage: Sendable {
        let image: CGImage
        var timestamp: Date  // 🔧 改为 var，允许更新
        let windowFrame: CGRect
        let windowHash: Int  // 用于快速比较窗口是否改变
        
        init(image: CGImage, frame: CGRect) {
            self.image = image
            self.timestamp = Date()
            self.windowFrame = frame
            
            // 计算窗口特征哈希（位置 + 尺寸）
            self.windowHash = frame.origin.x.hashValue ^
                            frame.origin.y.hashValue ^
                            frame.size.width.hashValue ^
                            frame.size.height.hashValue
        }
        
        // 🔧 更新时间戳（LRU 访问更新）
        mutating func touch() {
            self.timestamp = Date()
        }
    }
    
    // MARK: - Properties
    
    private var cache: [UInt32: CachedImage] = [:]
    private let maxCacheSize: Int
    private let maxCacheAge: TimeInterval  // 缓存最大有效期（秒）
    
    // 性能统计
    private var hitCount = 0
    private var missCount = 0
    
    // MARK: - Initialization
    
    init(maxSize: Int = 50, maxAge: TimeInterval = 15.0) {  // 🔧 延长到 15 秒
        self.maxCacheSize = maxSize
        self.maxCacheAge = maxAge
    }
    
    // MARK: - Public Methods
    
    /// 尝试从缓存获取窗口截图
    /// - Parameters:
    ///   - windowID: 窗口的系统 ID
    ///   - frame: 窗口当前的 frame
    /// - Returns: 如果缓存有效则返回图片，否则返回 nil
    func getImage(for windowID: UInt32, frame: CGRect) -> CGImage? {
        // windowID 为 0 表示虚拟窗口（无窗口的应用），不缓存
        guard windowID != 0 else { return nil }
        
        guard var cached = cache[windowID] else {
            missCount += 1
            return nil
        }
        
        // 检查缓存是否过期
        let age = Date().timeIntervalSince(cached.timestamp)
        if age > maxCacheAge {
            cache.removeValue(forKey: windowID)
            missCount += 1
            return nil
        }
        
        // 检查窗口尺寸/位置是否发生显著变化
        // 🔧 优化：放宽阈值到 20pt，避免因微小浮动导致缓存失效
        let frameDiff = abs(cached.windowFrame.width - frame.width) +
                       abs(cached.windowFrame.height - frame.height) +
                       abs(cached.windowFrame.origin.x - frame.origin.x) +
                       abs(cached.windowFrame.origin.y - frame.origin.y)
        
        // 如果总差异 > 20pt，认为窗口已改变，缓存失效
        if frameDiff > 20 {
            cache.removeValue(forKey: windowID)
            missCount += 1
            return nil
        }
        
        // 🔧 关键优化：缓存命中时更新时间戳（LRU 访问更新）
        cached.touch()
        cache[windowID] = cached
        
        // 缓存命中
        hitCount += 1
        return cached.image
    }
    
    /// 存储窗口截图到缓存
    /// - Parameters:
    ///   - image: 截图（已裁剪透明边缘）
    ///   - windowID: 窗口系统 ID
    ///   - frame: 窗口 frame
    func setImage(_ image: CGImage, for windowID: UInt32, frame: CGRect) {
        guard windowID != 0 else { return }
        
        cache[windowID] = CachedImage(image: image, frame: frame)
        
        // LRU 清理：如果缓存超过最大容量，移除最旧的条目
        if cache.count > maxCacheSize {
            cleanOldEntries()
        }
    }
    
    /// 清除指定窗口的缓存（例如窗口关闭时）
    func invalidate(windowID: UInt32) {
        cache.removeValue(forKey: windowID)
    }
    
    /// 清空所有缓存
    func clearAll() {
        cache.removeAll()
        hitCount = 0
        missCount = 0
    }
    
    /// 获取缓存统计信息
    func getStats() -> (hitRate: Double, cacheSize: Int, totalRequests: Int) {
        let total = hitCount + missCount
        let hitRate = total > 0 ? Double(hitCount) / Double(total) : 0.0
        return (hitRate: hitRate, cacheSize: cache.count, totalRequests: total)
    }
    
    // MARK: - Private Methods
    
    /// LRU 清理策略：移除最旧的缓存条目
    private func cleanOldEntries() {
        // 按时间排序，保留最新的 maxCacheSize 个条目
        let sorted = cache.sorted { $0.value.timestamp > $1.value.timestamp }
        let toKeep = sorted.prefix(maxCacheSize)
        cache = Dictionary(uniqueKeysWithValues: toKeep.map { ($0.key, $0.value) })
        
        print("🧹 WindowImageCache: Cleaned cache, retained \(cache.count) entries")
    }
}
