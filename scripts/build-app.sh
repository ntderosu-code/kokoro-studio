#!/bin/bash
# scripts/build-app.sh — build release binary and assemble self-contained Kokoro Studio.app
#
# Usage:
#   ./scripts/build-app.sh                 ad-hoc signed (local use / right-click-Open)
#   ./scripts/build-app.sh --release       Developer ID sign + notarize + staple + zip
#
# --release expects:
#   - a "Developer ID Application" cert in the keychain (SIGN_IDENTITY below)
#   - notarytool keychain profile "kokoro" (xcrun notarytool store-credentials kokoro ...)
#   - Sparkle release settings:
#       SPARKLE_PUBLIC_ED_KEY=<generate_keys public key>
#       SPARKLE_FEED_URL=https://.../appcast.xml (optional override)
set -euo pipefail
cd "$(dirname "$0")/.."

RELEASE=false
[ "${1:-}" = "--release" ] && RELEASE=true
SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application: BYRON ROBERT ROUSH (C25Q3Q4YFN)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-kokoro}"
DEFAULT_SPARKLE_FEED_URL="https://ntderosu-code.github.io/kokoro-studio/appcast.xml"
SPARKLE_FEED_URL="${SPARKLE_FEED_URL:-}"
SPARKLE_PUBLIC_ED_KEY="${SPARKLE_PUBLIC_ED_KEY:-}"
SPARKLE_ENABLE_AUTOMATIC_CHECKS="${SPARKLE_ENABLE_AUTOMATIC_CHECKS:-}"
SPARKLE_AUTOMATICALLY_UPDATE="${SPARKLE_AUTOMATICALLY_UPDATE:-}"
SPARKLE_VERIFY_BEFORE_EXTRACTION="${SPARKLE_VERIFY_BEFORE_EXTRACTION:-true}"

plist_bool() {
  case "$1" in
    true|TRUE|yes|YES|1) echo true ;;
    false|FALSE|no|NO|0) echo false ;;
    *) echo "Expected boolean value, got '$1'" >&2; exit 1 ;;
  esac
}

swift build -c release

APP="build/Kokoro Studio.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources"

cp .build/release/KokoroStudio "$APP/Contents/MacOS/Kokoro Studio"
# Real dylibs only (skip the version-symlink duplicates).
for dylib in vendor/sherpa-onnx/lib/*.dylib; do
  if [ ! -L "$dylib" ]; then
    cp "$dylib" "$APP/Contents/Frameworks/"
  fi
done
cp -R vendor/model "$APP/Contents/Resources/model"
cp -R vendor/pocket "$APP/Contents/Resources/pocket"
cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
SPARKLE_FRAMEWORK_SOURCE="$(find .build/artifacts -path "*/Sparkle.framework" -type d -print -quit)"
if [ -z "$SPARKLE_FRAMEWORK_SOURCE" ]; then
  echo "Could not find Sparkle.framework in .build/artifacts" >&2
  exit 1
fi
ditto "$SPARKLE_FRAMEWORK_SOURCE" "$APP/Contents/Frameworks/Sparkle.framework"

# Rewrite any absolute/local dylib references to @rpath so the bundled
# copies in Contents/Frameworks are used (the binary already carries an
# @executable_path/../Frameworks rpath from Package.swift).
BIN="$APP/Contents/MacOS/Kokoro Studio"
otool -L "$BIN" | awk 'NR>1 {print $1}' | grep -E "sherpa|onnxruntime" | while read -r ref; do
  name=$(basename "$ref")
  install_name_tool -change "$ref" "@rpath/$name" "$BIN"
done
# Fix inter-dylib references too (c-api links onnxruntime).
for dylib in "$APP/Contents/Frameworks/"*.dylib; do
  otool -L "$dylib" | awk 'NR>2 {print $1}' | grep -E "sherpa|onnxruntime" | while read -r ref; do
    name=$(basename "$ref")
    install_name_tool -change "$ref" "@loader_path/$name" "$dylib" 2>/dev/null || true
  done
done

# Drop the development-only rpath; bundled copies live in Contents/Frameworks.
install_name_tool -delete_rpath "vendor/sherpa-onnx/lib" "$BIN" 2>/dev/null || true

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Kokoro Studio</string>
  <key>CFBundleDisplayName</key><string>Kokoro Studio</string>
  <key>CFBundleIdentifier</key><string>com.byron.KokoroStudio</string>
  <key>CFBundleVersion</key><string>1.5.1</string>
  <key>CFBundleShortVersionString</key><string>1.5.1</string>
  <key>CFBundleExecutable</key><string>Kokoro Studio</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>Local Kokoro TTS via sherpa-onnx</string>
  <key>NSServices</key><array>
    <dict>
      <key>NSMenuItem</key><dict><key>default</key><string>Speak with Kokoro Studio</string></dict>
      <key>NSMessage</key><string>speakText</string>
      <key>NSPortName</key><string>Kokoro Studio</string>
      <key>NSSendTypes</key><array><string>NSStringPboardType</string></array>
    </dict>
    <dict>
      <key>NSMenuItem</key><dict><key>default</key><string>New Kokoro Studio Script</string></dict>
      <key>NSMessage</key><string>newScriptFromText</string>
      <key>NSPortName</key><string>Kokoro Studio</string>
      <key>NSSendTypes</key><array><string>NSStringPboardType</string></array>
    </dict>
  </array>
</dict></plist>
PLIST

if [ -z "$SPARKLE_FEED_URL" ] && [ -n "$SPARKLE_PUBLIC_ED_KEY" ]; then
  SPARKLE_FEED_URL="$DEFAULT_SPARKLE_FEED_URL"
fi

if [ -n "$SPARKLE_FEED_URL" ] || [ -n "$SPARKLE_PUBLIC_ED_KEY" ]; then
  if [ -z "$SPARKLE_FEED_URL" ] || [ -z "$SPARKLE_PUBLIC_ED_KEY" ]; then
    echo "SPARKLE_FEED_URL and SPARKLE_PUBLIC_ED_KEY must be set together" >&2
    exit 1
  fi
  case "$SPARKLE_FEED_URL" in
    https://*) ;;
    *) echo "SPARKLE_FEED_URL must use https" >&2; exit 1 ;;
  esac

  /usr/libexec/PlistBuddy -c "Add :SUFeedURL string $SPARKLE_FEED_URL" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $SPARKLE_PUBLIC_ED_KEY" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Add :SUVerifyUpdateBeforeExtraction bool $(plist_bool "$SPARKLE_VERIFY_BEFORE_EXTRACTION")" "$APP/Contents/Info.plist"
  if [ -n "$SPARKLE_ENABLE_AUTOMATIC_CHECKS" ]; then
    /usr/libexec/PlistBuddy -c "Add :SUEnableAutomaticChecks bool $(plist_bool "$SPARKLE_ENABLE_AUTOMATIC_CHECKS")" "$APP/Contents/Info.plist"
  fi
  if [ -n "$SPARKLE_AUTOMATICALLY_UPDATE" ]; then
    /usr/libexec/PlistBuddy -c "Add :SUAutomaticallyUpdate bool $(plist_bool "$SPARKLE_AUTOMATICALLY_UPDATE")" "$APP/Contents/Info.plist"
  fi
fi

sign_sparkle_framework() {
  local identity="$1"
  local framework="$APP/Contents/Frameworks/Sparkle.framework"
  local version_dir="$framework/Versions/B"
  local args=(--force --sign "$identity")

  # Hardened runtime + timestamp only for notarized releases. An ad-hoc
  # (team-less) app with hardened runtime gets library validation, which
  # refuses to load any bundled non-Apple framework — the app won't launch.
  if $RELEASE; then
    args+=(--options runtime --timestamp)
  fi

  [ -d "$framework" ] || return 0

  if [ -d "$version_dir/XPCServices/Installer.xpc" ]; then
    codesign "${args[@]}" "$version_dir/XPCServices/Installer.xpc"
  fi
  if [ -d "$version_dir/XPCServices/Downloader.xpc" ]; then
    codesign "${args[@]}" --preserve-metadata=entitlements "$version_dir/XPCServices/Downloader.xpc"
  fi
  if [ -e "$version_dir/Autoupdate" ]; then
    codesign "${args[@]}" "$version_dir/Autoupdate"
  fi
  if [ -d "$version_dir/Updater.app" ]; then
    codesign "${args[@]}" "$version_dir/Updater.app"
  fi
  codesign "${args[@]}" "$framework"
}

if $RELEASE; then
  echo "Signing with: $SIGN_IDENTITY"
  # Sign nested code first, then the app. Hardened runtime + secure
  # timestamp are required for notarization.
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" \
    "$APP/Contents/Frameworks/"*.dylib
  sign_sparkle_framework "$SIGN_IDENTITY"
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
  codesign --verify --deep --strict "$APP"

  echo "Submitting for notarization (uploads ~370MB, takes minutes)..."
  ditto -c -k --sequesterRsrc --keepParent "$APP" build/KokoroStudio.zip
  xcrun notarytool submit build/KokoroStudio.zip \
    --keychain-profile "$NOTARY_PROFILE" --wait

  xcrun stapler staple "$APP"
  ditto -c -k --sequesterRsrc --keepParent "$APP" build/KokoroStudio.zip
  echo "Notarized and stapled: build/KokoroStudio.zip"
else
  # No --options runtime here: see the library-validation note above.
  codesign --force --sign - "$APP/Contents/Frameworks/"*.dylib
  sign_sparkle_framework "-"
  codesign --force --sign - "$APP"
fi

echo "Built: $APP"
du -sh "$APP"
