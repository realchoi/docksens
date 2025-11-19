## DockSens

**DockSens 是一款专为 macOS 15 (Sequoia) 及更高版本打造的原生效率工具。它利用最新的 Apple 技术栈，通过 Dock 悬浮预览、现代化的窗口分屏以及增强型 Alt-Tab 切换器，全面提升 macOS 工作流体验。**

**DockSens: Supercharge your macOS workflow with Dock window previews, snapping, and a modern Alt-Tab switcher.**

(此处放置应用的主界面或功能演示截图 - 用于内部记录或将来展示)

### ✨ 核心功能 (Key Features)

#### 👀 Dock 悬浮预览 (Dock Previews)

- 鼠标悬停在 Dock 图标上时，即时显示该应用所有打开窗口的实时缩略图。

- 支持点击切换、快速关闭窗口。

- 采用 SwiftUI 6.0 的 .windowLevel(.floating) 实现原生级浮窗体验。

#### 🪟 窗口分屏管理 (Window Snapping)

- 强大的窗口吸附功能，轻松将窗口拖拽至屏幕边缘或角落进行分屏。

- 支持自定义快捷键（基于 App Intents）触发分屏布局（左/右半屏、四分之一屏、全屏）。

#### 🔄 增强型 Alt-Tab 切换器 (Modern App Switcher)

- 完全替代系统的 Cmd+Tab，提供带有大尺寸窗口预览的切换界面。

- 使用 SwiftUI PhaseAnimator 实现丝滑的选中动画。

- 支持键盘方向键导航，即便在后台也能流畅响应。


### ⚡️ 极致原生与性能

- 专为 Apple Silicon 优化。

- 极低的内存占用，利用 Swift 6 并发模型确保主线程零卡顿。


### 🛠 技术栈 (Tech Stack)

- 本项目采用最新的 macOS 开发技术栈：

- 最低系统要求: macOS 15.0 (Sequoia)

- 开发语言: Swift 6 (Strict Concurrency Checked)

- UI 框架: SwiftUI (利用 .containerRelativeFrame, Material Effects 等新特性)

- 状态管理: Observation Framework (@Observable 宏)

- 底层核心: Accessibility API (AXUIElement), Core Graphics

- 商业化: StoreKit 2 (SubscriptionStoreView 原生订阅界面)


### 💻 开发环境配置 (Dev Setup)

**环境要求**

- Xcode 16.0 或更高版本

- macOS 15.0 或更高版本

- Apple Developer Account (用于签名和内购测试)

- 权限调试 (Debug Permissions)


**由于应用依赖敏感的系统权限，在 Debug 模式下首次运行需要手动授权：**

- 构建并运行 App (Cmd + R)。

- 前往 **系统设置** -> **隐私与安全性**。

- 在 **辅助功能 (Accessibility)** 中添加 DockSens (Debug)。

- 在 **屏幕录制 (Screen Recording)** 中添加 DockSens (Debug)。

**注意：** 每次 Clean Build Folder 后，可能需要重新勾选权限。


### ⚖️ 版权与许可 (Copyright & License)

**Copyright © 2025 DockSens. All Rights Reserved.**

- 本项目为商业软件，保留所有权利。未经授权，禁止复制、分发或用于任何商业用途。

- 源代码仅供内部开发与维护使用。

- 依赖的第三方库遵循其各自的开源协议。

- Internal Development Documentation.