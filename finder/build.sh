#!/usr/bin/env bash
# Builds MergeFolders.app (host app + Finder Sync extension), ad-hoc signs it,
# installs it to /Applications, and registers the extension with Finder.
set -euo pipefail

here=$(cd -- "$(dirname -- "$0")" && pwd)
root=$(dirname -- "$here")
build="$here/build"
mkdir -p "$build"
stage=$(mktemp -d "$build/stage.XXXXXX")
trap 'rm -rf -- "$stage"' EXIT
app="$stage/MergeFolders.app"
ext="$app/Contents/PlugIns/MergeFoldersExt.appex"
bundle_id=com.devendra.mergefolders
ext_id=com.devendra.mergefolders.ext

case ${1-} in
  ""|--build-only) ;;
  *) echo "usage: $0 [--build-only]" >&2; exit 2 ;;
esac

echo "compiling…"
xcrun --sdk macosx swiftc -O -target "$(uname -m)-apple-macos13.0" -module-name MergeFoldersExt \
  -Xlinker -e -Xlinker _NSExtensionMain -o "$stage/MergeFoldersExt" "$here/FinderSyncExt.swift" -framework FinderSync
xcrun --sdk macosx swiftc -O -target "$(uname -m)-apple-macos13.0" -o "$stage/MergeFolders" "$here/HostApp.swift"

echo "assembling…"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" \
         "$ext/Contents/MacOS" "$ext/Contents/Resources"
cp "$stage/MergeFolders" "$app/Contents/MacOS/MergeFolders"
cp "$stage/MergeFoldersExt" "$ext/Contents/MacOS/MergeFoldersExt"
cp "$here/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
install -m 755 "$root/mergefolders" "$app/Contents/Resources/mergefolders"

cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key><string>en</string>
	<key>CFBundleURLTypes</key>
	<array><dict>
		<key>CFBundleURLName</key><string>$bundle_id.selection</string>
		<key>CFBundleURLSchemes</key><array><string>mergefolders</string></array>
	</dict></array>
	<key>CFBundleDisplayName</key><string>Merge Folders</string>
	<key>CFBundleExecutable</key><string>MergeFolders</string>
	<key>CFBundleIdentifier</key><string>$bundle_id</string>
	<key>CFBundleIconFile</key><string>AppIcon</string>
	<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
	<key>CFBundleName</key><string>MergeFolders</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>1.0</string>
	<key>CFBundleSupportedPlatforms</key><array><string>MacOSX</string></array>
	<key>CFBundleVersion</key><string>3</string>
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
	<key>CFBundleVersion</key><string>3</string>
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

cat > "$stage/ext.entitlements" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.app-sandbox</key><true/>
</dict>
</plist>
PLIST

echo "signing (ad-hoc)…"
codesign --force --sign - --entitlements "$stage/ext.entitlements" "$ext"
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"

# Keep the previous install until the replacement has been built and verified.
if [ "${1-}" = --build-only ]; then
  target="$build/MergeFolders.app"
else
  target="/Applications/MergeFolders.app"
fi
if [ -e "$target" ] && [ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$target/Contents/Info.plist" 2>/dev/null)" != "$bundle_id" ]; then
  echo "A different app already exists at $target. Move it before installing." >&2
  exit 1
fi
backup=$(mktemp -d "$(dirname "$target")/.mergefolders.XXXXXX")
if [ -e "$target" ]; then mv "$target" "$backup/"; fi
if ! mv "$app" "$target"; then
  if [ -e "$backup/MergeFolders.app" ]; then mv "$backup/MergeFolders.app" "$target"; fi
  rmdir "$backup"
  exit 1
fi
rm -rf -- "$backup"
echo "Built $target"
if [ "${1-}" = --build-only ]; then exit 0; fi

lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$lsregister" -f "$target"
pluginkit -a "$target/Contents/PlugIns/MergeFoldersExt.appex"
pluginkit -e use -i "$ext_id" || true
echo "If Merge Folders is not yet enabled, turn it on in System Settings under Finder Extensions."
