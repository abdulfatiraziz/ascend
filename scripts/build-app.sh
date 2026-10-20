#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/private/tmp/}ascend-module-cache"
configuration="${1:-release}"
for stage in obsidian titanium ascendant; do
  test -f "Sources/Ascend/Resources/Portraits/$stage.png"
done
swift build -c "$configuration" --disable-sandbox --cache-path "${TMPDIR:-/private/tmp/}ascend-swift-cache" --scratch-path .build
bin_dir=$(swift build -c "$configuration" --show-bin-path --disable-sandbox --cache-path "${TMPDIR:-/private/tmp/}ascend-swift-cache" --scratch-path .build)
app_dir="$PWD/build/Ascend.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$bin_dir/Ascend" "$app_dir/Contents/MacOS/Ascend"
ditto "$bin_dir/Ascend_Ascend.bundle" "$app_dir/Contents/Resources/Ascend_Ascend.bundle"
rm -rf "$app_dir/Contents/Resources/Ascend_Ascend.bundle/Avatar"
swift scripts/make-icon.swift "$PWD/build"
iconutil -c icns build/AppIcon.iconset -o "$app_dir/Contents/Resources/Ascend.icns"
cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Ascend</string>
<key>CFBundleIdentifier</key><string>com.abdul.ascend</string>
<key>CFBundleName</key><string>Ascend</string>
<key>CFBundleDisplayName</key><string>Ascend</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.6.0</string>
<key>CFBundleVersion</key><string>8</string>
<key>NSLocalNetworkUsageDescription</key><string>Ascend receives health data and meal photos from Ascend Bridge on your phone over your Wi-Fi.</string>
<key>NSBonjourServices</key><array><string>_ascend-sync._tcp</string></array>
<key>CFBundleIconFile</key><string>Ascend</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
# The phone app is offered for download over Wi-Fi; Android debugging tools are no longer bundled.
rm -rf "$app_dir/Contents/Resources/Android"
if [[ -f build/android/AscendBridge.apk ]]; then
  mkdir -p "$app_dir/Contents/Resources/Android"
  cp build/android/AscendBridge.apk "$app_dir/Contents/Resources/Android/AscendBridge.apk"
fi
codesign --force --deep --sign - "$app_dir"
echo "Built: $app_dir"
