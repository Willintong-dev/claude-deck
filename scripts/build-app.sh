#!/bin/zsh
set -euo pipefail

ROOT=${0:A:h:h}
APP="$HOME/Applications/ClaudeDeck.app"
HOOK_DIR="$HOME/.claude-deck/bin"

swift build --package-path "$ROOT" -c release --product deck-hook
swift build --package-path "$ROOT/App" -c release

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$HOOK_DIR"
cp "$ROOT/App/.build/release/ClaudeDeck" "$APP/Contents/MacOS/ClaudeDeck"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>local.claude-deck</string>
    <key>CFBundleName</key><string>Claude Deck</string>
    <key>CFBundleExecutable</key><string>ClaudeDeck</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP"

install -m 755 "$ROOT/.build/release/deck-hook" "$HOOK_DIR/deck-hook"
echo "App: $APP"
echo "Hook: $HOOK_DIR/deck-hook"
