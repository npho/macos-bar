#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"
swift build -c release
APP="$ROOT/.build/MenuBarGroups.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$ROOT/.build/release/MenuBarGroups" "$APP/Contents/MacOS/"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
# A stable development certificate keeps the app's signing identity consistent
# across rebuilds, so macOS privacy permissions can follow the same app. Without
# it, keep the existing ad-hoc local build for machines without a certificate.
if [[ -n "${MENU_BAR_GROUPS_SIGN_IDENTITY:-}" ]]; then
    codesign --force --sign "$MENU_BAR_GROUPS_SIGN_IDENTITY" --identifier com.example.MenuBarGroups "$APP"
fi
echo "Built: $APP"
