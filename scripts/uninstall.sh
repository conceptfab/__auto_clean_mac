#!/usr/bin/env bash
set -euo pipefail

BUNDLE_ID="com.micz.autocleanmac"
APP_DEST="$HOME/Applications/AutoCleanMac.app"
LAUNCH_AGENT="$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"
CONFIG_DIR="$HOME/.config/autoclean-mac"
LOGS_DIR="$HOME/Library/Logs/AutoCleanMac"

if [[ -f "$LAUNCH_AGENT" ]]; then
    echo "→ unloading LaunchAgent"
    launchctl unload "$LAUNCH_AGENT" 2>/dev/null || true
    rm -f "$LAUNCH_AGENT"
fi

if [[ -d "$APP_DEST" ]]; then
    echo "→ removing $APP_DEST"
    rm -rf "$APP_DEST"
fi

pkill -f "$APP_DEST/Contents/MacOS/AutoCleanMac" 2>/dev/null || true

read -r -p "Usunąć również konfigurację ($CONFIG_DIR)? [y/N] " answer
if [[ "$answer" =~ ^[Yy]$ ]]; then
    rm -rf "$CONFIG_DIR"
    echo "  usunięto."
fi

read -r -p "Usunąć również logi ($LOGS_DIR)? [y/N] " answer
if [[ "$answer" =~ ^[Yy]$ ]]; then
    rm -rf "$LOGS_DIR"
    echo "  usunięto."
fi

echo "✓ AutoCleanMac odinstalowany."
