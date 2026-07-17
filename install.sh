#!/bin/bash

# ==========================================
# XcodeCleaner 一键编译与应用打包脚本 (.app)
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
echo "🚀 开始编译并打包 XcodeCleaner.app..."
echo "=========================================="

# 创建临时工作目录并在退出时自动清理
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

SWIFT_FILE="$TMP_DIR/xcode_cleaner.swift"
SRC_ICON="$TMP_DIR/AppIcon.jpg"
APP_BUNDLE="$TMP_DIR/XcodeCleaner.app"
INSTALL_DIR="/Applications"
FINAL_APP="$INSTALL_DIR/XcodeCleaner.app"

# 3. 准备源码与图标资源文件
if [ "$IS_CURL_PIPE" = true ]; then
    echo "🌐 检测到通过 curl 管道运行，正在从 GitHub 自动下载最新源码与图标..."
    curl -fsSL "https://raw.githubusercontent.com/chenhuaizhe/XcodeCleaner/main/xcode_cleaner.swift" -o "$SWIFT_FILE"
    curl -fsSL "https://raw.githubusercontent.com/chenhuaizhe/XcodeCleaner/main/AppIcon.jpg" -o "$SRC_ICON"
else
    SRC_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
    if [ -f "$SRC_DIR/xcode_cleaner.swift" ]; then
        echo "📂 检测到本地源码文件，正在复制..."
        cp "$SRC_DIR/xcode_cleaner.swift" "$SWIFT_FILE"
    else
        echo "🌐 本地未找到源码文件，正在从 GitHub 自动下载最新源码..."
        curl -fsSL "https://raw.githubusercontent.com/chenhuaizhe/XcodeCleaner/main/xcode_cleaner.swift" -o "$SWIFT_FILE"
    fi
    
    if [ -f "$SRC_DIR/AppIcon.jpg" ]; then
        echo "🎨 检测到本地图标源文件，正在复制..."
        cp "$SRC_DIR/AppIcon.jpg" "$SRC_ICON"
    else
        echo "🌐 本地未找到图标，正在从 GitHub 自动下载最新图标..."
        curl -fsSL "https://raw.githubusercontent.com/chenhuaizhe/XcodeCleaner/main/AppIcon.jpg" -o "$SRC_ICON"
    fi
fi

# 4. 创建 .app 目录骨架
echo "📂 正在构建 App Bundle 骨架..."
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# 5. 自动合成 macOS 系统图标 (.icns)
if [ -f "$SRC_ICON" ]; then
    echo "🎨 正在生成 macOS 标准应用图标包 (.icns)..."
    # 用 sips 将 JPG 转换为 PNG
    sips -s format png "$SRC_ICON" --out "$TMP_DIR/AppIcon.png" >/dev/null 2>&1
    
    # 建立 iconset 目录
    mkdir -p "$TMP_DIR/AppIcon.iconset"
    
    # 利用 sips 缩放并输出各个标准尺寸的图标
    sips -z 16 16     "$TMP_DIR/AppIcon.png" --out "$TMP_DIR/AppIcon.iconset/icon_16x16.png" >/dev/null 2>&1
    sips -z 32 32     "$TMP_DIR/AppIcon.png" --out "$TMP_DIR/AppIcon.iconset/icon_16x16@2x.png" >/dev/null 2>&1
    sips -z 32 32     "$TMP_DIR/AppIcon.png" --out "$TMP_DIR/AppIcon.iconset/icon_32x32.png" >/dev/null 2>&1
    sips -z 64 64     "$TMP_DIR/AppIcon.png" --out "$TMP_DIR/AppIcon.iconset/icon_32x32@2x.png" >/dev/null 2>&1
    sips -z 128 128   "$TMP_DIR/AppIcon.png" --out "$TMP_DIR/AppIcon.iconset/icon_128x128.png" >/dev/null 2>&1
    sips -z 256 256   "$TMP_DIR/AppIcon.png" --out "$TMP_DIR/AppIcon.iconset/icon_128x128@2x.png" >/dev/null 2>&1
    sips -z 256 256   "$TMP_DIR/AppIcon.png" --out "$TMP_DIR/AppIcon.iconset/icon_256x256.png" >/dev/null 2>&1
    sips -z 512 512   "$TMP_DIR/AppIcon.png" --out "$TMP_DIR/AppIcon.iconset/icon_256x256@2x.png" >/dev/null 2>&1
    sips -z 512 512   "$TMP_DIR/AppIcon.png" --out "$TMP_DIR/AppIcon.iconset/icon_512x512.png" >/dev/null 2>&1
    sips -z 1024 1024 "$TMP_DIR/AppIcon.png" --out "$TMP_DIR/AppIcon.iconset/icon_512x512@2x.png" >/dev/null 2>&1
    
    # 合成 .icns 图标包并置于 Resources 目录下
    if command -v iconutil &> /dev/null; then
        iconutil -c icns "$TMP_DIR/AppIcon.iconset" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    fi
fi

# 6. 写入 Info.plist 配置文件
echo "✍️ 正在写入 Info.plist 配置文件..."
cat <<EOF > "$APP_BUNDLE/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>XcodeCleaner</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.chenhuaizhe.XcodeCleaner</string>
    <key>CFBundleName</key>
    <string>XcodeCleaner</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

# 7. 编译 Swift 二进制主程序
echo "📦 正在编译 Swift 源码至 App Bundle (开启 -O 优化)..."
swiftc -O "$SWIFT_FILE" -o "$APP_BUNDLE/Contents/MacOS/XcodeCleaner"

# 8. 部署应用包至 /Applications 目录
echo "🖥 正在安装应用至系统应用程序目录 (/Applications)..."
rm -rf "$FINAL_APP"
cp -R "$APP_BUNDLE" "$FINAL_APP"
echo "✅ 应用已成功安装: $FINAL_APP"

# 9. 创建全局终端快捷指令链接
echo "🔗 正在配置终端全局调用指令 (xcodeclean)..."
# 创建 /usr/local/bin 目录（如果不存在的话）
if [ ! -d "/usr/local/bin" ]; then
    echo "📂 正在创建 /usr/local/bin 目录..."
    sudo mkdir -p /usr/local/bin
fi

FINAL_BIN="$FINAL_APP/Contents/MacOS/XcodeCleaner"

# 软链接到全局路径，指向应用的编译二进制
if ln -sf "$FINAL_BIN" /usr/local/bin/xcodeclean 2>/dev/null; then
    echo "✅ 全局指令配置完成！您现在可以在终端的任意目录下输入 'xcodeclean' 直接运行软件。"
else
    echo "🔑 正在尝试使用管理员权限创建全局终端链接..."
    if sudo -n ln -sf "$FINAL_BIN" /usr/local/bin/xcodeclean 2>/dev/null; then
        echo "✅ 全局指令配置完成！您现在可以在终端的任意目录下输入 'xcodeclean' 直接运行软件。"
    else
        echo "⚠️ 权限限制：无法自动配置全局终端调用链接（若需全局调用，请手动执行: sudo ln -sf $FINAL_BIN /usr/local/bin/xcodeclean）"
    fi
fi

# 10. 解决可能存在的 App 缓存刷新问题以确保图标立刻显示
touch "$FINAL_APP"

echo "=========================================="
echo "🎉 安装完成！现在您可以选择以下方式使用该软件："
echo "=========================================="
echo " 1. [启动台 / Spotlight]：直接在 Spotlight (⌘ + 空格键) 中搜索并打开带图标的 'XcodeCleaner'。"
echo " 2. [全局命令行]：在终端中输入 'xcodeclean' 直接运行。"
echo " 3. [应用文件夹]：直接在 Finder 中双击打开: $FINAL_APP"
echo "=========================================="
