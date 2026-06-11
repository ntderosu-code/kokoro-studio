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
set -euo pipefail
cd "$(dirname "$0")/.."

RELEASE=false
[ "${1:-}" = "--release" ] && RELEASE=true
SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application: BYRON ROBERT ROUSH (C25Q3Q4YFN)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-kokoro}"

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
  <key>CFBundleVersion</key><string>1.4</string>
  <key>CFBundleShortVersionString</key><string>1.4</string>
  <key>CFBundleExecutable</key><string>Kokoro Studio</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>Local Kokoro TTS via sherpa-onnx</string>
</dict></plist>
PLIST

if $RELEASE; then
  echo "Signing with: $SIGN_IDENTITY"
  # Sign nested code first, then the app. Hardened runtime + secure
  # timestamp are required for notarization.
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" \
    "$APP/Contents/Frameworks/"*.dylib
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
  codesign --verify --deep --strict "$APP"

  echo "Submitting for notarization (uploads ~370MB, takes minutes)..."
  ditto -c -k --keepParent "$APP" build/KokoroStudio.zip
  xcrun notarytool submit build/KokoroStudio.zip \
    --keychain-profile "$NOTARY_PROFILE" --wait

  xcrun stapler staple "$APP"
  ditto -c -k --keepParent "$APP" build/KokoroStudio.zip
  echo "Notarized and stapled: build/KokoroStudio.zip"
else
  codesign --force --deep --sign - "$APP"
fi

echo "Built: $APP"
du -sh "$APP"
