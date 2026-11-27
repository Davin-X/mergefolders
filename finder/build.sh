#!/usr/bin/env bash
# Builds MergeFolders.app (host app + Finder Sync extension) for Apple silicon
# and Intel, signs it, installs it to /Applications, and registers the
# extension with Finder. SIGN_IDENTITY="Developer ID Application: …" signs for
# notarization; the default "-" signs ad-hoc for local use.
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
sign_identity=${SIGN_IDENTITY:--}
# The CLI script holds the only version number.
version=$(sed -n 's/^VERSION=//p' "$root/mergefolders")
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "no VERSION=x.y.z in mergefolders" >&2; exit 1; }
IFS=. read -r major minor patch <<<"$version"
build_number=$((major * 10000 + minor * 100 + patch))  # 0.3.0 -> 300; must keep rising

case ${1-} in
  ""|--build-only) ;;
  *) echo "usage: $0 [--build-only]" >&2; exit 2 ;;
esac

echo "compiling ${version}…"
for arch in arm64 x86_64; do
  xcrun --sdk macosx swiftc -O -target "$arch-apple-macos13.0" -module-name MergeFoldersExt \
    -Xlinker -e -Xlinker _NSExtensionMain -o "$stage/MergeFoldersExt-$arch" "$here/FinderSyncExt.swift" -framework FinderSync
  xcrun --sdk macosx swiftc -O -target "$arch-apple-macos13.0" -o "$stage/MergeFolders-$arch" "$here/HostApp.swift"
done
lipo -create -output "$stage/MergeFoldersExt" "$stage/MergeFoldersExt-arm64" "$stage/MergeFoldersExt-x86_64"
lipo -create -output "$stage/MergeFolders" "$stage/MergeFolders-arm64" "$stage/MergeFolders-x86_64"

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
	<key>CFBundleShortVersionString</key><string>$version</string>
	<key>CFBundleSupportedPlatforms</key><array><string>MacOSX</string></array>
	<key>CFBundleVersion</key><string>$build_number</string>
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
	<key>CFBundleShortVersionString</key><string>$version</string>
	<key>CFBundleSupportedPlatforms</key><array><string>MacOSX</string></array>
	<key>CFBundleVersion</key><string>$build_number</string>
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

if [ "$sign_identity" = - ]; then
  echo "signing (ad-hoc)…"
  sign=(codesign --force --sign -)
else
  echo "signing as ${sign_identity}…"
  sign=(codesign --force --options runtime --timestamp --sign "$sign_identity")
fi
"${sign[@]}" --entitlements "$stage/ext.entitlements" "$ext"
"${sign[@]}" "$app"
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
