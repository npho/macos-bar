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

# Auto-detect Apple Development identity from keychain if not explicitly set
SIGN_IDENTITY="${MENU_BAR_GROUPS_SIGN_IDENTITY:-}"
if [[ -z "$SIGN_IDENTITY" ]]; then
    SIGN_IDENTITY=$(security find-identity -v -p codesigning | grep "Apple Development" | head -n 1 | awk '{print $2}' || true)
fi

if [[ -n "$SIGN_IDENTITY" ]]; then
    echo "Signing with stable identity: $SIGN_IDENTITY"
    codesign --force --sign "$SIGN_IDENTITY" --identifier com.example.MenuBarGroups "$APP"
else
    echo "No Apple Development identity found; leaving ad-hoc signature."
fi
echo "Built: $APP"
