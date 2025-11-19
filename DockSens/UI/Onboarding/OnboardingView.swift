//
//  OnboardingView.swift
//  DockSens
//
//  Created by DockSens Team.
//

import SwiftUI

struct OnboardingView: View {
    // 持久化存储：记录用户是否完成了引导
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding: Bool = false
    
    @State private var navigationPath = NavigationPath()
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            WelcomeView(onNext: {
                navigationPath.append(OnboardingStep.permissions)
            })
            .navigationDestination(for: OnboardingStep.self) { step in
                switch step {
                case .permissions:
                    PermissionGrantView(isOnboardingFinished: $hasCompletedOnboarding)
                        // 隐藏返回按钮，强制流程
                        .navigationBarBackButtonHidden(true)
                }
            }
        }
        .frame(width: 700, height: 500) // 设定引导窗口的最佳尺寸
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    enum OnboardingStep {
        case permissions
    }
}

// 第一页：欢迎页
struct WelcomeView: View {
    let onNext: () -> Void
    
    var body: some View {
        VStack(spacing: 40) {
            Spacer()
            
            Image(systemName: "dock.rectangle") // 占位 Logo
                .font(.system(size: 80))
                .foregroundStyle(
                    LinearGradient(colors: [.blue, .purple], startPoint: .top, endPoint: .bottom)
                )
                .shadow(radius: 10)
            
            VStack(spacing: 16) {
                Text("Welcome to DockSens")
                    .font(.system(size: 36, weight: .bold))
                
                Text("Supercharge your macOS Dock with live window previews\nand powerful window management.")
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button(action: onNext) {
                HStack {
                    Text("Get Started")
                    Image(systemName: "arrow.right")
                }
                .font(.headline)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction) // 允许按回车进入下一页
            
            Spacer().frame(height: 40)
        }
        .padding()
    }
}

#Preview {
    OnboardingView()
}