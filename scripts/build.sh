#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$PROJECT_DIR/build/Pankaj Mac Cleanup.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
xcrun swiftc -O -swift-version 5 -parse-as-library -target "$(uname -m)-apple-macosx13.0" \
  "$PROJECT_DIR/Sources/CleanupCore.swift" "$PROJECT_DIR/Sources/FileReviewCore.swift" \
  "$PROJECT_DIR/Sources/MacCleanup.swift" "$PROJECT_DIR/Sources/FileReviewUI.swift" \
  -framework SwiftUI -framework AppKit -o "$APP_DIR/Contents/MacOS/MacCleanup"
cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Pankaj Mac Cleanup</string>
<key>CFBundleDisplayName</key><string>Pankaj Mac Cleanup</string>
<key>CFBundleIdentifier</key><string>com.pankajbhadrecha.mac-cleanup</string>
<key>CFBundleExecutable</key><string>MacCleanup</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.1.0</string>
<key>CFBundleVersion</key><string>2</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSHumanReadableCopyright</key><string>Copyright 2026 Pankaj Bhadrecha. MIT License.</string>
</dict></plist>
PLIST
xattr -cr "$APP_DIR"
codesign --force --sign - "$APP_DIR"
echo "Built: $APP_DIR"
du -sh "$APP_DIR"
