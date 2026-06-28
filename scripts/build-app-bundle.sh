#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# Prefer full Xcode if installed (required when xcode-select points to CLT)
if [[ -d "/Applications/Xcode.app/Contents/Developer" ]]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

APP_NAME="AutoCleanMac"
BUNDLE_ID="com.micz.autocleanmac"
VERSION="0.1.0"
BUILD_DIR="$REPO_ROOT/.build/release"
MENU_SOURCE="$REPO_ROOT/Sources/AutoCleanMacMenuObjC/main.m"
MENU_EXECUTABLE="$BUILD_DIR/AutoCleanMacMenuObjC"
UI_EXECUTABLE="AutoCleanMacUI"
OUT_DIR="$REPO_ROOT/.build/bundle"
DIST_DIR="$REPO_ROOT/dist"
DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION.dmg"
DMG_STAGING="$OUT_DIR/dmg-staging"
APP_DIR="$OUT_DIR/$APP_NAME.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RESOURCES_DIR="$APP_DIR/Contents/Resources"

echo "→ swift build -c release"
swift build -c release

echo "→ clang menu helper"
clang -fobjc-arc -framework AppKit -framework Carbon "$MENU_SOURCE" -o "$MENU_EXECUTABLE"

echo "→ assembling bundle at $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$MENU_EXECUTABLE" "$MACOS_DIR/$APP_NAME"
cp "$BUILD_DIR/$APP_NAME" "$MACOS_DIR/$UI_EXECUTABLE"
chmod +x "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$UI_EXECUTABLE"

if [[ -f "$REPO_ROOT/resources/$APP_NAME.icns" ]]; then
    cp "$REPO_ROOT/resources/$APP_NAME.icns" "$RESOURCES_DIR/$APP_NAME.icns"
fi

for menubar_icon in MenuBarIcon.png MenuBarIcon@2x.png; do
    if [[ -f "$REPO_ROOT/resources/$menubar_icon" ]]; then
        cp "$REPO_ROOT/resources/$menubar_icon" "$RESOURCES_DIR/$menubar_icon"
    fi
done

cat > "$APP_DIR/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>       <string>en</string>
    <key>CFBundleExecutable</key>              <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>                <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>              <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>   <string>6.0</string>
    <key>CFBundleName</key>                    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>             <string>APPL</string>
    <key>CFBundleShortVersionString</key>      <string>$VERSION</string>
    <key>CFBundleVersion</key>                 <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>          <string>13.0</string>
    <key>LSUIElement</key>                     <true/>
    <key>NSHighResolutionCapable</key>         <true/>
    <key>NSAppleEventsUsageDescription</key>   <string>AutoCleanMac używa Findera do przeniesienia chronionych aplikacji do Kosza podczas deinstalacji.</string>
</dict>
</plist>
EOF

echo "→ ad-hoc codesign (obie binarki + bundle, spójnie dla TCC/Full Disk Access)"
# Najpierw zagnieżdżona binarka UI (to ona czyści pliki — TCC sprawdza jej tożsamość),
# potem główna binarka i cały bundle. Bez tego Full Disk Access nadane bundlowi
# nie obejmuje procesu czyszczącego uruchamianego przez NSTask.
codesign --force --sign - --timestamp=none "$MACOS_DIR/$UI_EXECUTABLE"
codesign --force --sign - --timestamp=none "$MACOS_DIR/$APP_NAME"
codesign --force --deep --sign - --timestamp=none "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR" && echo "   codesign OK"

echo "→ packaging DMG (drag-to-install)"
mkdir -p "$DIST_DIR"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
cp -R "$APP_DIR" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"
rm -f "$DMG_PATH"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_STAGING" \
    -ov -format UDZO \
    "$DMG_PATH"
rm -rf "$DMG_STAGING"

echo "→ done:"
echo "   app: $APP_DIR"
echo "   dmg: $DMG_PATH"
