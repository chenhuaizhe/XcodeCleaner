#!/bin/bash

# ==========================================
# XcodeCleaner 一键编译与部署脚本
# ==========================================

# 确保脚本发生错误时立刻退出
set -e

# 1. 检查是否为 curl | bash 管道模式
IS_CURL_PIPE=false
if [ -z "${BASH_SOURCE[0]}" ] || [ "${BASH_SOURCE[0]}" = "bash" ]; then
    IS_CURL_PIPE=true
fi

# 2. 检查 swiftc 编译器
if ! command -v swiftc &> /dev/null; then
    echo "❌ 错误: 未检测到 swiftc 编译器！"
    echo "💡 请确保您的 Mac 已经安装了 Xcode 或者是 Command Line Tools。"
    echo "   您可以通过运行 'xcode-select --install' 来进行安装。"
    exit 1
fi

echo "=========================================="
echo "🚀 开始编译并安装 XcodeCleaner..."
echo "=========================================="

# 创建临时工作目录并在退出时自动清理
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

SWIFT_FILE="$TMP_DIR/xcode_cleaner.swift"
INSTALL_DIR="/Applications"
OUT_BIN="$INSTALL_DIR/XcodeCleaner"

# 3. 准备源码文件
if [ "$IS_CURL_PIPE" = true ]; then
    echo "🌐 检测到通过 curl 管道运行，正在从 GitHub 自动下载最新源码..."
    curl -fsSL "https://raw.githubusercontent.com/chenhuaizhe/XcodeCleaner/main/xcode_cleaner.swift" -o "$SWIFT_FILE"
else
    SRC_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
    if [ -f "$SRC_DIR/xcode_cleaner.swift" ]; then
        echo "📂 检测到本地源码文件，正在复制..."
        cp "$SRC_DIR/xcode_cleaner.swift" "$SWIFT_FILE"
    else
        echo "🌐 本地未找到源码文件，正在从 GitHub 自动下载最新源码..."
        curl -fsSL "https://raw.githubusercontent.com/chenhuaizhe/XcodeCleaner/main/xcode_cleaner.swift" -o "$SWIFT_FILE"
    fi
fi

# 4. 开始编译并输出到最终 /Applications 目录
echo "📦 正在编译 Swift 源码 (开启 -O 速度优化)..."
swiftc -O "$SWIFT_FILE" -o "$OUT_BIN"
echo "✅ 编译成功！生成可执行程序: $OUT_BIN"

# 5. 创建全局命令行工具链接
echo "🔗 正在配置终端全局调用指令 (xcodeclean)..."
# 创建 /usr/local/bin 目录（如果不存在的话）
if [ ! -d "/usr/local/bin" ]; then
    echo "📂 正在创建 /usr/local/bin 目录..."
    sudo mkdir -p /usr/local/bin
fi

# 软链接到全局路径，指向 /Applications/XcodeCleaner
if ln -sf "$OUT_BIN" /usr/local/bin/xcodeclean 2>/dev/null; then
    echo "✅ 全局指令配置完成！您现在可以在终端 of 任意目录下输入 'xcodeclean' 直接运行软件。"
else
    echo "🔑 正在尝试使用管理员权限创建全局终端链接..."
    if sudo -n ln -sf "$OUT_BIN" /usr/local/bin/xcodeclean 2>/dev/null; then
        echo "✅ 全局指令配置完成！您现在可以在终端的任意目录下输入 'xcodeclean' 直接运行软件。"
    else
        echo "⚠️ 权限限制：无法自动配置全局终端调用链接（若需全局调用，请手动执行: sudo ln -sf $OUT_BIN /usr/local/bin/xcodeclean）"
    fi
fi

echo "=========================================="
echo "🎉 安装完成！现在您可以选择以下方式使用该软件："
echo "=========================================="
echo " 1. [启动台 / Spotlight]：直接在 Spotlight (⌘ + 空格键) 中搜索 'XcodeCleaner' 回车运行。"
echo " 2. [全局命令行]：在终端中输入 'xcodeclean' 直接运行。"
echo " 3. [访达双击]：在 Finder 中直接双击该可执行程序："
echo "    $OUT_BIN"
echo "=========================================="
