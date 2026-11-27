#!/usr/bin/env bash
# Installs the mergefolders command and the MergeFolders.app Finder extension.
set -euo pipefail

here=$(cd -- "$(dirname -- "$0")" && pwd)
bin="$HOME/bin"

mkdir -p "$bin"
install -m 755 "$here/mergefolders" "$bin/mergefolders"

# Finder app: build, sign, install, register extension.
echo "installing Finder app…"
bash "$here/finder/build.sh"

echo "installed: $bin/mergefolders"
echo "finder app: /Applications/MergeFolders.app"
echo
echo "Try:  $bin/mergefolders --dry-run --to /tmp \"some folder\" \"another folder\""
echo "Finder: select 2+ folders, right-click, “Merge Folders…”"
echo "If it is missing: System Settings → General → Login Items & Extensions → Extensions → Finder."
