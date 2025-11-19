import os
import textwrap
import json

def create_file(path, content):
    """创建文件并写入内容，如果父目录不存在则创建父目录"""
    dir_name = os.path.dirname(path)
    if dir_name and not os.path.exists(dir_name):
        os.makedirs(dir_name)
    
    with open(path, 'w', encoding='utf-8') as f:
        f.write(content.strip() + "\n")
    print(f"Created: {path}")

def generate_header(filename, imports, intent):
    """生成 Swift 文件头、Import 语句和 TODO 注释"""
    import_stmts = "\n".join([f"import {lib}" for lib in imports])
    
    return textwrap.dedent(f"""
        //
        //  {filename}
        //  DockSens
        //
        //  Created by DockSens Setup Script.
        //

        {import_stmts}

        // TODO: {intent}
        // ---------------------------------------------------------
        
        """)

def main():
    root_dir = "DockSens_Project_Structure"
    
    # --- 1. 定义多语言 String Catalog (Localizable.xcstrings) ---
    # 这是一个标准的 JSON 格式，Xcode 会自动识别并提供可视化编辑器。
    xcstrings_content = json.dumps({
        "sourceLanguage" : "en",
        "strings" : {
            "Settings" : {
                "localizations" : {
                    "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "设置" } }
                }
            },
            "Quit" : {
                "localizations" : {
                    "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "退出" } }
                }
            },
            "General" : {
                "localizations" : {
                    "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "通用" } }
                }
            },
            "Shortcuts" : {
                "localizations" : {
                    "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "快捷键" } }
                }
            },
            "Pro" : {
                "localizations" : {
                    "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "专业版" } }
                }
            },
            "Unlock Pro" : {
                "localizations" : {
                    "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "解锁专业版" } }
                }
            },
            "NEW" : {
                "comment" : "Badge label for new features",
                "localizations" : {
                    "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "新" } }
                }
            },
            "Toggle Window Switcher" : {
                "comment" : "App Intent title",
                "localizations" : {
                    "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "切换窗口切换器" } }
                }
            },
            "Launch at Login" : {
                "localizations" : {
                    "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "开机自启" } }
                }
            },
            "Restore Purchases" : {
                "localizations" : {
                    "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "恢复购买" } }
                }
            }
        },
        "version" : "1.0"
    }, indent=2, ensure_ascii=False)

    files_config = {
        # ==========================================
        # 0. Resources (新增)
        # ==========================================
        f"{root_dir}/Resources/Localizable.xcstrings": (
            "Localizable.xcstrings",
            [], 
            "多语言字符串目录 (String Catalog)。支持英语(开发语言)和简体中文。",
            xcstrings_content # 这是一个特殊的处理，不需要 generate_header
        ),

        # ==========================================
        # 1. App & 全局状态
        # ==========================================
        f"{root_dir}/App/DockSensApp.swift": (
            "DockSensApp.swift",
            ["SwiftUI", "AppIntents"], 
            "App 入口。注入全局 AppState。",
            """
@main
struct DockSensApp: App {
    @State private var appState = AppState()
    
    var body: some Scene {
        Settings {
            SettingsView()
                .environment(appState)
        }
        
        MenuBarExtra("DockSens", systemImage: "dock.rectangle") {
            // SwiftUI 会自动查找 Localizable.xcstrings 中的 "Settings" 和 "Quit"
            Button("Settings") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
            """
        ),
        f"{root_dir}/Core/State/AppState.swift": (
            "AppState.swift",
            ["SwiftUI", "Observation"],
            "全局单一事实来源。整合 WindowManager 和 StoreService 的状态。",
            """
@MainActor
@Observable
final class AppState {
    // --- 核心状态 ---
    var runningWindows: [WindowInfo] = []
    var isSwitcherVisible: Bool = false
    var isPro: Bool = false // 内购状态
    
    // --- 内部服务 ---
    private let windowManager = WindowManager()
    private let storeService = StoreService()
    
    init() {
        Task { await startMonitoringWindows() }
        Task { await startMonitoringPurchases() }
    }
    
    private func startMonitoringWindows() async {
        for await windows in windowManager.windowsStream() {
            self.runningWindows = windows
        }
    }
    
    private func startMonitoringPurchases() async {
        for await status in storeService.proStatusStream() {
            self.isPro = status
        }
    }
    
    func toggleSwitcher() {
        guard !isSwitcherVisible else { 
            windowManager.hideSwitcher()
            isSwitcherVisible = false
            return
        }
        windowManager.showSwitcher()
        isSwitcherVisible = true
    }
}
            """
        ),

        # ==========================================
        # 2. Core - 核心逻辑
        # ==========================================
        f"{root_dir}/Core/WindowManager/WindowManager.swift": (
            "WindowManager.swift",
            ["AppKit", "Foundation"],
            "主线程窗口控制器。管理 NSPanel 实例的生命周期。",
            """
@MainActor
class WindowManager {
    private var switcherPanel: NSPanel?
    private let engine = WindowEngine()
    
    func showSwitcher() { /* ... */ }
    func hideSwitcher() { switcherPanel?.orderOut(nil) }
    
    func windowsStream() -> AsyncStream<[WindowInfo]> {
        return AsyncStream { _ in }
    }
}
            """
        ),
        f"{root_dir}/Core/WindowManager/WindowEngine.swift": (
            "WindowEngine.swift",
            ["ApplicationServices", "CoreGraphics"],
            "后台 Actor。负责繁重的 AXUIElement 查询。",
            """
struct WindowInfo: Identifiable, Sendable {
    let id: Int
    let title: String
    let appName: String
    let frame: CGRect
}

actor WindowEngine {
    func scanWindows() async -> [WindowInfo] {
        return []
    }
}
            """
        ),
        f"{root_dir}/Core/Store/StoreService.swift": (
            "StoreService.swift",
            ["StoreKit", "Foundation"],
            "内购逻辑服务。",
            """
actor StoreService {
    private let proProductID = "com.docksens.pro.lifetime"

    nonisolated func proStatusStream() -> AsyncStream<Bool> {
        return AsyncStream { continuation in
            Task { await updateStatus(continuation: continuation) }
            Task {
                for await _ in Transaction.updates {
                    await updateStatus(continuation: continuation)
                }
            }
        }
    }
    
    private func updateStatus(continuation: AsyncStream<Bool>.Continuation) async {
        var hasPro = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, transaction.productID == proProductID {
                hasPro = true
                break
            }
        }
        continuation.yield(hasPro)
    }
}
            """
        ),
        f"{root_dir}/Core/Shortcuts/GlobalShortcuts.swift": (
            "GlobalShortcuts.swift",
            ["AppKit", "AppIntents"],
            "定义全局热键名称和 App Intents。",
            """
// import KeyboardShortcuts

struct ToggleSwitcherIntent: AppIntent {
    // AppIntents 自动支持 LocalizedStringResource。
    // 这里的字符串键值 "Toggle Window Switcher" 会自动匹配 .xcstrings 中的条目。
    static var title: LocalizedStringResource = "Toggle Window Switcher"
    
    @MainActor
    func perform() async throws -> some IntentResult {
        // 这里需要访问全局状态，实际开发中建议使用 Dependency Injection 系统
        // let appState = ...
        return .result()
    }
}
            """
        ),

        # ==========================================
        # 3. UI - 界面层
        # ==========================================
        f"{root_dir}/UI/Store/StoreView.swift": (
            "StoreView.swift",
            ["SwiftUI", "StoreKit"],
            "内购界面。",
            """
struct ProStoreView: View {
    var body: some View {
        SubscriptionStoreView(groupID: "group.com.docksens.pro") {
            VStack {
                Image(systemName: "sparkles").font(.largeTitle)
                // SwiftUI 会自动查找翻译
                Text("Unlock Pro").font(.title2)
            }
            .containerBackground(.blue.gradient, for: .subscriptionStoreHeader)
        }
        // 甚至系统提供的按钮文案也可以自定义 Key
        .storeButton(.visible, for: .restorePurchases)
    }
}
            """
        ),
        f"{root_dir}/UI/Settings/SettingsView.swift": (
            "SettingsView.swift",
            ["SwiftUI"],
            "设置窗口。",
            """
struct SettingsView: View {
    @Environment(AppState.self) var appState
    
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gear") }
            
            Text("Shortcuts Placeholder")
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
                
            ProStoreView()
                .tabItem { 
                    Label("Pro", systemImage: appState.isPro ? "star.fill" : "star") 
                }
                .badge(appState.isPro ? nil : "NEW")
        }
        .scenePadding()
        .frame(minWidth: 500, minHeight: 400)
    }
}
            """
        ),
        f"{root_dir}/UI/Settings/GeneralSettingsView.swift": (
            "GeneralSettingsView.swift",
            ["SwiftUI"],
            "通用设置。",
            """
struct GeneralSettingsView: View {
    // 这是一个简单的占位符，展示如何使用 Localized Key
    @AppStorage("launchAtLogin") var launchAtLogin = false
    
    var body: some View {
        Form {
            // "Launch at Login" 键值在 .xcstrings 中已有中文翻译
            Toggle("Launch at Login", isOn: $launchAtLogin)
        }
        .padding()
    }
}
            """
        ),

        # ==========================================
        # 4. Utilities
        # ==========================================
        f"{root_dir}/Utilities/Permissions.swift": (
            "Permissions.swift",
            ["AppKit"],
            "权限检查工具。",
            "enum Permissions { static func isAccessibilityTrusted() -> Bool { AXIsProcessTrusted() } }"
        ),
    }

    print(f"🚀 开始生成 DockSens (macOS 15+ Modern Arch, with Localization) 项目结构...")

    for path, (filename, imports, intent, content_or_tuple) in files_config.items():
        if filename.endswith(".xcstrings"):
            # 特殊处理 .xcstrings，它不需要 Swift header
            create_file(path, content_or_tuple)
        else:
            file_content = generate_header(filename, imports, intent)
            if content_or_tuple:
                file_content += content_or_tuple
            else:
                file_content += f"// 代码实现...\n// class {filename.split('.')[0]} {{ }}"
            create_file(path, file_content)

    print(f"\n✅ 升级完毕！包含多语言资源。")
    print("👉 操作指南：")
    print("1. 将 'Resources' 文件夹拖入 Xcode 项目。")
    print("2. Xcode 会自动识别 Localizable.xcstrings。")
    print("3. 运行 App 时，如果系统语言是中文，你会看到界面已自动汉化。")

if __name__ == "__main__":
    main()