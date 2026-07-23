#!/bin/zsh
# Build Vitrine.app — native SwiftUI, Liquid Glass, macOS 26+
set -e
cd "$(dirname "$0")"

swift build -c release

APP="build/Vitrine.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Vitrine "$APP/Contents/MacOS/Vitrine"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Vitrine</string>
    <key>CFBundleIdentifier</key><string>com.zzw4257.vitrine</string>
    <key>CFBundleName</key><string>Vitrine</string>
    <key>CFBundleDisplayName</key><string>Vitrine</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.1.0</string>
    <key>CFBundleVersion</key><string>2</string>
    <key>CFBundleIconFile</key><string>Vitrine.icns</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>© 2026 zzw4257</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
</dict>
</plist>
PLIST

# App icon: generated once by Tools/makeicon.swift, cached afterwards
if [[ ! -f build/Vitrine.icns ]]; then
  swift Tools/makeicon.swift build/icon.iconset
  iconutil -c icns build/icon.iconset -o build/Vitrine.icns
fi
cp build/Vitrine.icns "$APP/Contents/Resources/Vitrine.icns"

codesign --force -s - "$APP" 2>/dev/null
echo "✓ Built $APP"
