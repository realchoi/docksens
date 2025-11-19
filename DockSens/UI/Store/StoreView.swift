//
//  StoreView.swift
//  DockSens
//
//  Created by DockSens Team.
//

import SwiftUI
import StoreKit

struct ProStoreView: View {
    @Environment(\.dismiss) private var dismiss
    // FIX 1: 引入全局 AppState 以获取同步的订阅状态
    @Environment(AppState.self) private var appState
    
    var body: some View {
        // 核心：一行代码调起系统级内购页
        SubscriptionStoreView(productIDs: StoreService.productIDs) {
            // MARK: - 营销内容区域 (Marketing Content)
            VStack(spacing: 20) {
                Image(systemName: "macwindow.on.rectangle") // 你的 App Logo
                    .font(.system(size: 60))
                    .foregroundStyle(.white)
                    .shadow(radius: 10)
                
                VStack(spacing: 8) {
                    Text("Unlock DockSens Pro")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                    
                    Text("Experience window management at the speed of thought.")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                }
                
                // 功能列表 (Feature List)
                VStack(alignment: .leading, spacing: 12) {
                    FeatureRow(icon: "dock.rectangle", text: "Live Dock Previews")
                    FeatureRow(icon: "command", text: "Fast Window Switcher")
                    FeatureRow(icon: "keyboard", text: "Custom Shortcuts")
                }
                .padding(.top, 20)
            }
            .padding(40)
            // MARK: - 营销背景
            .containerBackground(for: .subscriptionStoreHeader) {
                LinearGradient(
                    colors: [Color.blue, Color.purple],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        // MARK: - 控件定制
        // FIX 2: 忽略闭包参数（因为 Info 对象无法同步读取状态），改用 appState.isPro
        .subscriptionStoreControlIcon { _, _ in
            Group {
                if appState.isPro {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .symbolEffect(.bounce, value: appState.isPro) // 添加一点成功动画
                } else {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                }
            }
        }
        // 显示“恢复购买”按钮
        .storeButton(.visible, for: .restorePurchases)
        // 显示“政策”链接
        .storeButton(.visible, for: .policies)
        // 设置内购页面的样式
        .subscriptionStorePickerItemBackground(.thinMaterial)
        .frame(minWidth: 500, minHeight: 600)
    }
}

// 简单的辅助视图
struct FeatureRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .frame(width: 30)
                .foregroundStyle(.white)
            Text(text)
                .font(.body)
                .fontWeight(.medium)
                .foregroundStyle(.white)
        }
    }
}

#Preview {
    ProStoreView()
        .environment(AppState()) // 预览需注入 Environment
}