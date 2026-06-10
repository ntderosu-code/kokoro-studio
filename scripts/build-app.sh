#!/bin/bash
# scripts/build-app.sh — build release binary and assemble self-contained Kokoro Studio.app
set -euo pipefail
cd "$(dirname "$0")/.."

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
  <key>CFBundleVersion</key><string>1.0</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleExecutable</key><string>Kokoro Studio</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>Local Kokoro TTS via sherpa-onnx</string>
</dict></plist>
PLIST

codesign --force --deep --sign - "$APP"
echo "Built: $APP"
du -sh "$APP"
