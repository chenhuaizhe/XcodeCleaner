---
name: xcode-cleaner
description: Scan and clean Xcode caches, DerivedData, iOS DeviceSupport, and simulator devices safely.
---

# XcodeCleaner Agent Skill

本 Skill 旨在指导 AI 助手 (Agent) 自动化或辅助用户管理和清理 macOS 下的 Xcode 垃圾文件及模拟器，以释放磁盘空间。

## 🔍 触发场景 (Triggers)
当用户提到以下主题时，AI 助手应主动阅读并应用本 Skill：
* "清理 Xcode 缓存/垃圾", "释放 Xcode 空间"
* "DerivedData 怎么删", "Archives 太多了"
* "清除旧模拟器", "删除不可用模拟器", "simctl delete unavailable"

---

## 🛠 AI 操作指南 (Agent Instructions)

本项目的核心源文件是 [xcode_cleaner.swift](file:///Users/cy/.gemini/antigravity/scratch/XcodeCleaner/xcode_cleaner.swift)。它提供了一个功能完整的原生 GUI 和底层清理引擎。

作为 AI，如果用户要求你**自动帮其清理**，你可以无需打开 GUI，直接在后台通过命令行辅助用户清理，或引导用户编译并打开该 GUI 工具。

### 1. 指引用户编译并运行 GUI 工具 (推荐)
如果你建议用户使用可视化界面进行多维度勾选，可以直接在终端执行编译和运行：
```bash
# 一键编译并安装
bash /Users/cy/.gemini/antigravity/scratch/XcodeCleaner/install.sh
```

### 2. 自动在终端中帮助用户清理
如果用户要求你（AI）直接帮他删除某些缓存，你应当使用 `run_command` 来安全地操作：

* **清理无用/不可用模拟器**（利用系统 API）:
  ```bash
  xcrun simctl delete unavailable
  ```
* **一键清除全部 DerivedData** (安全，下次编译时会自动重建):
  ```bash
  rm -rf ~/Library/Developer/Xcode/DerivedData/*
  ```
* **一键清除 SwiftUI Previews 缓存**:
  ```bash
  rm -rf ~/Library/Developer/Xcode/UserData/Previews/*
  ```
* **一键清除真机调试符号 (DeviceSupport)**:
  > [!WARNING]
  > 仅建议删除旧版本的系统符号。可以先运行 `ls ~/Library/Developer/Xcode/iOS\ DeviceSupport` 看看有哪些版本，然后针对性地 `rm -rf` 那些您不再使用的老旧 OS 版本（例如 iOS 15 以前）。

---

## 📄 模拟器信息检索 (For AI Reference)
如果您（AI）需要手动分析当前用户本地有哪些模拟器，可以通过运行以下 Python 代码块来拉取列表，这比运行大型 `du` 速度快得多：

```python
import os, plistlib
devices_path = os.path.expanduser('~/Library/Developer/CoreSimulator/Devices')
for d in os.listdir(devices_path):
    plist = os.path.join(devices_path, d, 'device.plist')
    if os.path.exists(plist):
        with open(plist, 'rb') as f:
            data = plistlib.load(f)
            print(f"UUID: {d} | Name: {data.get('name')} | Runtime: {data.get('runtime')}")
```
