#!/bin/bash
# 编译并打包成 .app（ad-hoc 签名，个人自用）
set -euo pipefail
cd "$(dirname "$0")"

APP="RightClick.app"

echo "==> 编译 release"
swift build -c release

echo "==> 组装 ${APP}"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/RightClick" "$APP/Contents/MacOS/RightClick"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"
cp "Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

echo "==> ad-hoc 签名"
codesign --force --sign - --identifier "com.luca.rightclick" "$APP"

echo "==> 完成: $(pwd)/${APP}"
echo "提示：每次重新签名后，macOS 可能把旧授权视为失效，需要在「系统设置 → 隐私与安全性 → 辅助功能」里移除旧条目再重新添加。"
