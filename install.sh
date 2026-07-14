#!/bin/bash

# ==========================================
# XcodeCleaner 一键编译与部署脚本
# ==========================================

# 确保脚本发生错误时立刻退出
set -e

# 获取脚本所在的绝对路径
SRC_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SWIFT_FILE="$SRC_DIR/xcode_cleaner.swift"
OUT_BIN="$SRC_DIR/XcodeCleaner"

echo "=========================================="
echo "🚀 开始编译并安装 XcodeCleaner..."
echo "=========================================="

# 1. 检查 swiftc 编译器
if ! command -v swiftc &> /dev/null; then
    echo "❌ 错误: 未检测到 swiftc 编译器！"
    echo "💡 请确保您的 Mac 已经安装了 Xcode 或者是 Command Line Tools。"
    echo "   您可以通过运行 'xcode-select --install' 来进行安装。"
    exit 1
fi

# 2. 开始编译
echo "📦 正在编译 Swift 单文件源码 (开启 -O 速度优化)..."
swiftc -O "$SWIFT_FILE" -o "$OUT_BIN"
echo "✅ 编译成功！生成可执行程序: $OUT_BIN"

# 3. 创建全局命令行工具链接
echo "🔗 正在配置终端全局调用指令 (xcodeclean)..."
# 创建 /usr/local/bin 目录（如果不存在的话）
if [ ! -d "/usr/local/bin" ]; then
    echo "📂 正在创建 /usr/local/bin 目录..."
    sudo mkdir -p /usr/local/bin
fi

# 软链接到全局路径，并自动覆盖旧链接
if ln -sf "$OUT_BIN" /usr/local/bin/xcodeclean 2>/dev/null; then
    echo "✅ 全局指令配置完成！您现在可以在终端的任意目录下输入 'xcodeclean' 直接运行软件。"
else
    echo "🔑 正在尝试使用管理员权限创建全局终端链接..."
    if sudo -n ln -sf "$OUT_BIN" /usr/local/bin/xcodeclean 2>/dev/null; then
        echo "✅ 全局指令配置完成！您现在可以在终端的任意目录下输入 'xcodeclean' 直接运行软件。"
    else
        echo "⚠️ 权限限制：无法自动配置全局终端调用链接（若需全局调用，请手动执行: sudo ln -sf $OUT_BIN /usr/local/bin/xcodeclean）"
    fi
fi

# 4. 创建 Application 软链接以便 Spotlight 检索和在启动台中显示
echo "🖥 正在将其链接到系统应用程序目录 (/Applications)..."
# 软链接到 Applications 目录
ln -sf "$OUT_BIN" /Applications/XcodeCleaner

echo "=========================================="
echo "🎉 安装完成！现在您可以选择以下方式使用该软件："
echo "=========================================="
echo " 1. [启动台 / Spotlight]：直接在 Spotlight (⌘ + 空格键) 中搜索 'XcodeCleaner' 回车运行。"
echo " 2. [全局命令行]：在终端中输入 'xcodeclean' 直接运行。"
echo " 3. [访达双击]：在 Finder 中直接双击该可执行程序："
echo "    $OUT_BIN"
echo "=========================================="
