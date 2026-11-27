# Merge Folders

Move the contents of two or more folders into one. Name clashes are never
overwritten — the incoming item becomes `name (2).ext`.

Two ways in: a Finder right-click item (app), and a command-line tool. They
share the same `mergefolders` script.

## Install

```sh
./install.sh
```

Installs the command-line tool (`mergefolders` → `~/bin`) and the **Merge
Folders…** Finder extension.

The Finder app is built by `finder/build.sh` (needs Xcode), ad-hoc signed, and
registered with the PlugInKit database.

## Use

- **Finder (recommended):** select 2+ folders in Finder → right-click →
  **Merge Folders…** → pick the destination in the window that opens → **Merge**.
- **Terminal:**

```sh
mergefolders --to ~/Pictures/Merged ~/Pictures/2023 ~/Pictures/2024
mergefolders --dry-run --to ~/Pictures/Merged ~/Pictures/2023   # preview only
```

## What it does

- Merges each selected folder's **contents** into the destination, so
  same-named subfolders combine and files keep their relative path.
- Files passed directly are moved into the destination.
- Existing names are never replaced: `x.jpg` → `x (2).jpg` → `x (3).jpg`.
- Source folders are deleted once empty (`.DS_Store` is dropped, not moved).
  Use `--keep` to leave them.
- The destination may be one of the selected folders.
- Refuses a destination inside a source folder.

## Flags

| flag | meaning |
| --- | --- |
| `--to DIR` | destination (default: choose in Finder) |
| `--dry-run` | print the plan, change nothing |
| `--keep` | keep empty source folders |
| `--notify` | macOS notification when done (used by the Finder app) |

## Uninstall

```sh
rm ~/bin/mergefolders
rm -rf /Applications/MergeFolders.app
pluginkit -a "/Applications/MergeFolders.app/Contents/PlugIns/MergeFoldersExt.appex"   # may not clear DB
```

## Caveats

- No undo. Keep-both renaming is the only safety net.
- Make sure iCloud/Dropbox files are downloaded before moving them.
- The app is ad-hoc signed (no Developer ID), which is fine locally but would
  need real signing + notarization to share/distribute.
