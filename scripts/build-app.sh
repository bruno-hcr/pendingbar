#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications}"
BIN_LINK_DIR="${BIN_LINK_DIR:-$HOME/.local/bin}"
APP="$ROOT/build.noindex/PendingBar.app"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

cd "$ROOT"
xcrun swift build -c release
BIN="$(xcrun swift build -c release --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/PendingBar" "$APP/Contents/MacOS/PendingBar"
cp "$BIN/pendingctl" "$APP/Contents/MacOS/pendingctl"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
xcrun actool "$ROOT/Resources/Assets.xcassets" --compile "$APP/Contents/Resources" \
  --platform macosx --minimum-deployment-target 14.0 --app-icon AppIcon \
  --output-partial-info-plist "$ROOT/build.noindex/actool-partial.plist" >/dev/null
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(date +%Y%m%d%H%M%S)" "$APP/Contents/Info.plist"

codesign --force --sign - --timestamp=none "$APP/Contents/MacOS/pendingctl"
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --deep --strict "$APP"

if [[ "${1:-}" == "--install" ]]; then
  if pgrep -x PendingBar >/dev/null; then
    pkill -x PendingBar || true
    sleep 1
  fi
  mkdir -p "$INSTALL_DIR" "$BIN_LINK_DIR"
  rm -rf "$INSTALL_DIR/PendingBar.app"
  cp -R "$APP" "$INSTALL_DIR/PendingBar.app"
  ln -sf "$INSTALL_DIR/PendingBar.app/Contents/MacOS/pendingctl" "$BIN_LINK_DIR/pendingctl"
  "$LSREGISTER" -u "$APP" >/dev/null 2>&1 || true
  rm -rf "$APP"
  "$LSREGISTER" -f "$INSTALL_DIR/PendingBar.app"
  open "$INSTALL_DIR/PendingBar.app"
  echo "Installed $INSTALL_DIR/PendingBar.app and linked $BIN_LINK_DIR/pendingctl"
else
  echo "Built $APP (run with --install to install and launch)"
fi
