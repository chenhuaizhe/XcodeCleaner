# XcodeCleaner 项目开发背景与技术演进纪实

## 📖 项目起源与痛点

在 macOS 下进行 iOS/macOS 应用程序开发时，Xcode 往往会悄无声息地蚕食数十甚至数百 GB 的磁盘空间。其主要的垃圾来源包括：
1. **DerivedData (编译缓存)**：项目编译过程中产生的中间临时文件和索引。
2. **iOS DeviceSupport (真机调试支持)**：每次连接真机进行调试时，Xcode 都会在本地生成巨量的真机调试符号包。
3. **Simulators (模拟器设备)**：各个模拟器的应用沙盒数据、应用本身，特别是当 Xcode 升级或重装后，系统中会遗留大量已经失效的“不可用 (Unavailable) 模拟器”。

虽然市面上存在诸如 CleanMyMac 等第三方清理软件，但大部分是闭源收费的，或者只提供粗暴的“一键全删”，极易误删常用的编译索引导致下次编译速度慢。

为了治好开发者的“空间焦虑”，`XcodeCleaner` 应运而生。

---

## 🛠 架构设计决策：极客式的“单文件 Swift GUI”

在传统的 macOS App 开发中，我们需要创建复杂的 `.xcodeproj`，并受限于苹果严苛的沙盒保护（App Sandbox）。沙盒内的应用绝对无法直接访问或清理外部的用户目录（如 `~/Library/Developer`），除非用户进行繁琐的文件授权，开发体验极差。

为了打破这一僵局，本项目做出了一个具有极客色彩的架构决策：**单文件 Swift 源码直接编译为无沙盒限制的原生桌面 GUI 应用**。
* **技术原理**：通过在单个 `xcode_cleaner.swift` 文件中直接导入 `AppKit` 与 `SwiftUI`，手动在代码尾部拉起 `NSApplication` 事件主循环（`NSApp.run()`），将 SwiftUI 视图包裹在原生窗口 `NSWindow` 中呈现。
* **免沙盒权限**：直接在终端通过编译器 `swiftc` 对其进行编译。这种编译方式生成的二进制程序**默认不带任何沙盒限制**，它能够完美继承启动终端或当前用户的全部读写权限，从而可以极其强悍、快速地完成 `~/Library/` 目录下文件的扫描与清除。

---

## 🚀 项目技术演进历程 (Technical Evolution)

### 阶段一：极简 Mach-O 命令行 GUI 雏形
* **实现**：用一个 `xcode_cleaner.swift` 源码文件，完成了多线程后台扫描模块（使用 `FileManager` 的深度深度遍历，确保 UI 不卡死），支持对 DerivedData、Archives、DeviceSupport、Caches 的扫描，并在界面上实现多选批量物理删除。

### 阶段二：模拟器高阶筛选引擎
* **实现**：针对模拟器（Simulators）进行了深度定制。支持读取 `device.plist` 解析设备名称和系统运行时版本，同时结合 `xcrun simctl list --json` 解析当前设备的可用性状态。
* **功能**：在界面引入了“型号与系统筛选”复合过滤器。能够自动提取用户本地已有的设备型号（如 iPhone, iPad, Apple Watch）和系统版本（如 iOS 18.0, iOS 18.2）进行多选勾选。同时支持**一键清理不可用设备**（调用底层的 `xcrun simctl delete unavailable`）。

### 阶段三：中英双语自适应 (I18n) 重构
* **实现**：由于开源需要面向全球，但单文件不方便携带传统的 `.strings` 本地化资源包。我们在代码中实现了一个轻量的语言自适应函数 `localize(zh:en:)`，通过检测 `Locale.preferredLanguages` 首选项，使得同一套二进制在中文系统下显示中文，在英文系统下显示英文。

### 阶段四：工程化开源建设与 AI Agent 友好化
* **实现**：
  * 引入 [install.sh](install.sh) 自动化脚本，处理编译和终端全局调用链接的创建。
  * 编写 [README.md](README.md) 并集成了 **AI Agent 一键部署提示词**，方便其他开发者将 Prompt 直接复制给 Cursor、Gemini、Claude 等 AI 助手来自动完成部署。
  * 封装了标准的 [SKILL.md](.agents/skills/xcode-cleaner/SKILL.md) 技能文档，使其他的 AI 助手加载后，能够主动掌握并在后台自动运行该清理能力。

### 阶段五： macOS 原生桌面包 (.app) 自动化封装
* **实现**：为了解决二进制裸文件没有图标且在 Finder 中显示不佳的问题，我们重写了 [install.sh](install.sh)。
  1. **多尺寸图标合成**：利用系统内置的 `sips` 图像命令，将 AI 绘制的 App 图标 `AppIcon.jpg` 缩放并输出为 10 个子分辨率尺寸，最后用 `iconutil` 合成为 macOS 标准的 `AppIcon.icns` 图标包。
  2. **手写 Info.plist**：用脚本动态为 App 写入必要的配置项，构建了一个标准的 `XcodeCleaner.app` 目录结构，并放置在系统的 `/Applications/`（应用程序）中。
  3. **系统层关联**：用户不仅可以在 Spotlight（聚焦搜索）中直接检索到带 3D 锤子图标的应用，而且终端里的 `xcodeclean` 指令也被无缝关联到了应用包内的二进制文件。

### 阶段六：解决 macOS 独立应用的完全磁盘访问权限限制
* **实现**：
  * **发现问题**：打包成 `.app` 独立运行后，脱离了终端的权限继承，受限于 macOS TCC 安全控制，导致双击运行时 FileManager 读取敏感目录被静默拦截，表现为“什么也扫不出来”。
  * **解决思路**：在 `xcode_cleaner.swift` 中重构了扫描逻辑，对目录读取进行 Cocoa 257 (Permission Denied) 错误捕获。一旦检测到拦截，在界面上方会弹出醒目的“完全磁盘访问权限 (Full Disk Access)”红色警告引导栏，并提供一键直达 macOS 隐私设置页面的跳转深层链接（Deep Link），极大提升了人机交互体验。

---

## 👨‍💻 开发者信息

* **项目所有者**：[chenhuaizhe](https://github.com/chenhuaizhe)  
* **GitHub 仓库**：[https://github.com/chenhuaizhe/XcodeCleaner](https://github.com/chenhuaizhe/XcodeCleaner)
