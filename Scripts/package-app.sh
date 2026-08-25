#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")/.."
swift build -c release
BIN=".build/release/MacPaper"
APP="MacPaper.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MacPaper"
cp Sources/MacPaper/Resources/Info.plist "$APP/Contents/Info.plist"
chmod +x "$APP/Contents/MacOS/MacPaper"

if command -v codesign >/dev/null; then
  codesign --force --sign - "$APP" >/dev/null 2>&1 || true
fi

echo "Built $APP"
echo "Open with: open $APP"
