#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

APP_NAME="AutoCleanMac"
BUNDLE_ID="com.micz.autocleanmac"
INSTALL_DIR="$HOME/Applications"
APP_DEST="$INSTALL_DIR/$APP_NAME.app"
LAUNCH_AGENT="$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"
CONFIG_DIR="$HOME/.config/autoclean-mac"
CONFIG_FILE="$CONFIG_DIR/config.json"
LOGS_DIR="$HOME/Library/Logs/AutoCleanMac"

if ! xcode-select -p >/dev/null 2>&1; then
    echo "Command Line Tools are not installed."
    echo "Uruchom: xcode-select --install"
    exit 1
fi

echo "→ building .app bundle"
"$REPO_ROOT/scripts/build-app-bundle.sh"

echo "→ installing to $APP_DEST"
mkdir -p "$INSTALL_DIR"
rm -rf "$APP_DEST"
cp -R "$REPO_ROOT/.build/bundle/$APP_NAME.app" "$APP_DEST"

echo "→ ensuring log directory"
mkdir -p "$LOGS_DIR"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "→ writing default config to $CONFIG_FILE"
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_FILE" <<'JSON'
{
  "retention_days": 7,
  "window": { "fade_in_ms": 800, "hold_after_ms": 3000, "fade_out_ms": 800 },
  "tasks": {
    "user_caches": true,
    "system_temp": true,
    "trash": true,
    "ds_store": true,
    "user_logs": true,
    "browser_caches": true,
    "dev_caches": true,
    "downloads": false
  }
}
JSON
else
    echo "→ config exists at $CONFIG_FILE (leaving untouched)"
fi

echo "→ installing LaunchAgent"
mkdir -p "$(dirname "$LAUNCH_AGENT")"
sed \
    -e "s|__APP_BINARY__|$APP_DEST/Contents/MacOS/$APP_NAME|g" \
    -e "s|__LOGS_DIR__|$LOGS_DIR|g" \
    "$REPO_ROOT/resources/com.micz.autocleanmac.plist.template" > "$LAUNCH_AGENT"

launchctl unload "$LAUNCH_AGENT" 2>/dev/null || true
launchctl load -w "$LAUNCH_AGENT"

echo ""
echo "✓ AutoCleanMac zainstalowany."
echo "  • Aplikacja:     $APP_DEST"
echo "  • Konfiguracja:  $CONFIG_FILE"
echo "  • Logi:          $LOGS_DIR"
echo "  • LaunchAgent:   $LAUNCH_AGENT"
echo ""
echo "Możesz uruchomić ręcznie: open \"$APP_DEST\""
echo "Deinstalacja: ./scripts/uninstall.sh"
