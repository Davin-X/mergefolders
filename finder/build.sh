#!/usr/bin/env bash
# Builds MergeFolders.app (host app + Finder Sync extension), ad-hoc signs it,
# installs it to /Applications, and registers the extension with Finder.
set -euo pipefail

here=$(cd -- "$(dirname -- "$0")" && pwd)
root=$(dirname -- "$here")
app="/Applications/MergeFolders.app"
ext="$app/Contents/PlugIns/MergeFoldersExt.appex"
build="$here/build"
bundle_id=com.devendra.mergefolders
ext_id=com.devendra.mergefolders.ext

rm -rf "$build" "$app"
mkdir -p "$build"

echo "compiling…"
xcrun --sdk macosx swiftc -O -target "$(uname -m)-apple-macos13.0" -module-name MergeFoldersExt \
  -o "$build/MergeFoldersExt" "$here/FinderSyncExt.swift" -framework FinderSync
xcrun --sdk macosx swiftc -O -target "$(uname -m)-apple-macos13.0" -o "$build/MergeFolders" "$here/HostApp.swift"

echo "assembling…"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" \
         "$ext/Contents/MacOS" "$ext/Contents/Resources"
cp "$build/MergeFolders" "$app/Contents/MacOS/MergeFolders"
cp "$build/MergeFoldersExt" "$ext/Contents/MacOS/MergeFoldersExt"
cp "$here/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
install -m 755 "$root/mergefolders" "$ext/Contents/Resources/mergefolders"

cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key><string>en</string>
	<key>CFBundleDisplayName</key><string>Merge Folders</string>
	<key>CFBundleExecutable</key><string>MergeFolders</string>
	<key>CFBundleIdentifier</key><string>$bundle_id</string>
	<key>CFBundleIconFile</key><string>AppIcon</string>
	<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
	<key>CFBundleName</key><string>MergeFolders</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>1.0</string>
	<key>CFBundleSupportedPlatforms</key><array><string>MacOSX</string></array>
	<key>CFBundleVersion</key><string>1</string>
	<key>DTPlatformName</key><string>macosx</string>
	<key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
	<key>LSMinimumSystemVersion</key><string>13.0</string>
	<key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

cat > "$ext/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key><string>en</string>
	<key>CFBundleDisplayName</key><string>Merge Folders</string>
	<key>CFBundleExecutable</key><string>MergeFoldersExt</string>
	<key>CFBundleIdentifier</key><string>$ext_id</string>
	<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
	<key>CFBundleName</key><string>MergeFoldersExt</string>
	<key>CFBundlePackageType</key><string>XPC!</string>
	<key>CFBundleShortVersionString</key><string>1.0</string>
	<key>CFBundleSupportedPlatforms</key><array><string>MacOSX</string></array>
	<key>CFBundleVersion</key><string>1</string>
	<key>DTPlatformName</key><string>macosx</string>
	<key>LSMinimumSystemVersion</key><string>13.0</string>
	<key>NSExtension</key>
	<dict>
		<key>NSExtensionPointIdentifier</key><string>com.apple.FinderSync</string>
		<key>NSExtensionPrincipalClass</key><string>FinderSync</string>
	</dict>
</dict>
</plist>
PLIST

plutil -lint "$app/Contents/Info.plist" "$ext/Contents/Info.plist" >/dev/null

cat > "$build/ext.entitlements" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.app-sandbox</key><true/>
</dict>
</plist>
PLIST

echo "signing (ad-hoc)…"
codesign --force --sign - --entitlements "$build/ext.entitlements" "$ext"
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"

echo "registering…"
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$lsregister" -f "$app" || true
pluginkit -a "$ext" || true
pluginkit -e use -i "$ext_id" || true

# Finder caches its menu; restarting it makes the new item appear immediately.
killall Finder 2>/dev/null || true

echo
echo "installed: $app"
echo "extension: $ext"
pluginkit -m -p com.apple.FinderSync | grep -i mergefolders || echo "(extension not listed yet — enable it in System Settings → General → Login Items & Extensions → Finder Extensions)"
echo
echo "Try: select 2+ folders in Finder → right-click → “Merge Folders…”"
echo "If it is missing: open MergeFolders.app, or System Settings → General → Login Items & Extensions → Finder Extensions."
