//
//  StoreService.swift
//  DockSens
//
//  Created by DockSens Team.
//

import StoreKit
import Foundation

/// 极简 Store Actor
/// 职责：
/// 1. 提供产品 ID (Product IDs)
/// 2. 监听交易状态 (Transaction Updates) 以更新 AppState
actor StoreService {
    
    // MARK: - Configuration
    
    // 定义产品 ID。实际项目中应与 App Store Connect 后台一致。
    // 支持数组，例如 ["com.docksens.pro.monthly", "com.docksens.pro.lifetime"]
    static let productIDs: [String] = ["com.docksens.pro.lifetime"]
    
    // 这是一个具体的 ID，用于逻辑判断
    static let proLifetimeID = "com.docksens.pro.lifetime"

    // MARK: - Status Stream
    
    /// 不需要手动写购买逻辑 (purchase)，SubscriptionStoreView 会自动处理。
    /// 我们只需要监听结果来解锁功能。
    nonisolated func proStatusStream() -> AsyncStream<Bool> {
        return AsyncStream { continuation in
            // 1. 初始检查
            Task {
                await updateStatus(continuation: continuation)
            }
            
            // 2. 监听未来的交易更新 (StoreKit 2 自动处理)
            Task {
                for await _ in Transaction.updates {
                    await updateStatus(continuation: continuation)
                }
            }
        }
    }
    
    private func updateStatus(continuation: AsyncStream<Bool>.Continuation) async {
        var hasPro = false
        // 检查当前有效的 Entitlements
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                // 只要用户拥有我们列表中的任意一个产品，即视为 Pro
                if StoreService.productIDs.contains(transaction.productID) {
                    hasPro = true
                    break
                }
            }
        }
        continuation.yield(hasPro)
    }
}