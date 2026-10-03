#!/bin/bash
# 打包 ccBaton.app 到项目的 dist 目录
set -euo pipefail
cd "$(dirname "$0")/.."

# 1、编译发布版
swift build -c release --arch arm64

# 2、组装应用包
APP=dist/ccBaton.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/arm64-apple-macosx/release/ccBaton "$APP/Contents/MacOS/ccBaton"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# 3、本机签名
codesign --force --deep --sign - "$APP"
echo "$PWD/$APP"
