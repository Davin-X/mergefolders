<p align="center"><img src="docs/assets/icon.png" width="100" alt="Merge Folders icon"></p>

# Merge Folders for macOS

Combine folders from Finder or Terminal. If two folders contain `Trips/beach.jpg`, the first photo keeps its name and the incoming photo becomes `Trips/beach (2).jpg`. The app **moves** the originals. Use Preview in Finder or the Terminal example below to see the planned moves before changing your files.

[![Latest release](https://img.shields.io/github/v/release/Davin-X/mergefolders?label=Download)](https://github.com/Davin-X/mergefolders/releases/latest)

[Illustrated guide](https://davin-x.github.io/mergefolders/) · [Installation](#install) · [Finder walkthrough](#merge-from-finder) · [Terminal quick start](#try-the-cli-with-sample-files) · [File handling](#what-happens-to-my-files) · [Uninstall](#update-or-uninstall)

## Install

1. Download the source ZIP from the [latest release](https://github.com/Davin-X/mergefolders/releases/latest), or use **Code → Download ZIP** on the repository page. Unzip it. If you already cloned the repository, use that folder.
2. Open Terminal, type `cd ` (including the space), drag the extracted folder into the window, then press Return.
3. Choose an installation below.

| What you want | Run in Terminal | Installed location |
| --- | --- | --- |
| Finder menu and Terminal command | `./install.sh` | `/Applications/MergeFolders.app` and `~/bin/mergefolders` |
| Terminal command only | `./install.sh --cli-only` | `~/bin/mergefolders` |

The Finder app requires macOS 13 or later, write access to `/Applications`, and Apple’s Command Line Tools. To install the tools, run `xcode-select --install`, finish the Apple installer, then run `./install.sh`. The CLI-only option uses the Bash and file utilities included with macOS and skips compilation.

## Merge from Finder

1. Open **System Settings**, search for **Extensions**, find **Finder Extensions**, and enable **Merge Folders**. The settings location varies by macOS version.
2. In a Finder window, Command-click the source folders or files. Right-click the selection and choose **Merge Folders…**.
3. **Choose the destination.** Check that Camera and Phone are both listed. Click **Choose…** and select or create the Album folder.

   <img src="docs/assets/merge-choose.png" width="500" alt="Merge Folders lists Camera and Phone. Choose is available, and Preview and Merge are disabled until a destination is selected.">

4. **Preview the names.** Click **Preview**. The last planned path ends in `beach (2).jpg`, so both photos will be kept. The dry run leaves the sources in place.

   <img src="docs/assets/merge-preview.png" width="500" alt="Preview lists two planned moves into Album and shows the second photo becoming beach (2).jpg.">

5. **Merge and inspect the result.** Click **Merge**. In this example the summary reports two files moved, one renamed, and zero failures. Click **Open Folder** to see both photos, or **Done** to close the window.

   <img src="docs/assets/merge-result.png" width="500" alt="Completed merge with Open Folder available, Done ready to close the window, and a summary of two moved, one renamed, zero skipped, and zero failed.">

If the menu is missing, open **MergeFolders** from Applications, use **Open Finder Extensions…**, and check the switch. Reopen the Finder window after enabling it.

## Try the CLI with sample files

Paste this into Terminal. It creates a fresh practice folder with two files of the same name and previews the merge.

```sh
demo=$(mktemp -d)
mkdir -p "$demo/First" "$demo/Second" "$demo/Merged"
printf 'first copy\n' > "$demo/First/note.txt"
printf 'second copy\n' > "$demo/Second/note.txt"
~/bin/mergefolders --dry-run --to "$demo/Merged" "$demo/First" "$demo/Second"
```

To perform the merge and see both files, run these commands in the same Terminal window.

```sh
~/bin/mergefolders --to "$demo/Merged" "$demo/First" "$demo/Second"
ls "$demo/Merged"
```

The destination now contains `note.txt` and `note (2).txt`. For your own files, replace the three folder paths. Put paths containing spaces in quotes. You can also drag folders from Finder into Terminal to enter their paths.

| Option | Use |
| --- | --- |
| `--to DIR` | Merge into an existing directory. Omit this option to choose one in a dialog. |
| `--dry-run`, `-n` | Preview planned file moves and names. |
| `--keep` | Leave the source directory structure in place after moving its files. |
| `--notify` | Display a macOS notification on completion or a dialog on failure. |
| `--help` | Print usage and exit. |

## What happens to my files?

- Files retain their relative paths. Same-named subdirectories combine. A naming conflict adds the first available suffix, starting at ` (2)`, before the last extension.
- Selected symbolic links move as links. Relative links keep their stored target text, so moving one can change where it resolves. A symlink beneath the destination cannot serve as a parent for incoming files.
- Empty source directories are pruned after a move unless you use `--keep`. Empty directories are not created in the destination. Finder’s `.DS_Store` files inside sources are skipped.
- You can select the destination as one of the source folders. The tool skips it. A destination nested inside another source is rejected.
- A merge performs individual moves. If it stops partway, completed moves stay in place. Read the error, check the destination, then preview the remaining sources before retrying. Keep a backup when merging important files. There is no built-in undo.
- Download cloud-only files before merging. For a Finder merge, diagnostic output is saved to `~/Library/Logs/MergeFolders.log`.

## Update or uninstall

To update, download the new source or update your clone, then rerun the installation command you originally chose.

To uninstall the Finder integration, quit Merge Folders, disable its Finder extension in System Settings, and run the following commands. Unregister the extension while the app is still installed.

```sh
pluginkit -r "/Applications/MergeFolders.app/Contents/PlugIns/MergeFoldersExt.appex"
```

Move **MergeFolders.app** from Applications to the Trash. To remove the Terminal command, run `rm -i "$HOME/bin/mergefolders"`.

## Development and release checks

```sh
bash tests/test_mergefolders.sh
bash finder/build.sh --build-only
```

The second command compiles and ad-hoc signs the app at `finder/build/MergeFolders.app`. CI verifies the signature, checks the extension linkage, and runs the bundled CLI. The public installation instructions build from source. Distributing a ready-made app requires a separate signing and notarization workflow for a standard Gatekeeper installation experience.

Before tagging a release, test the documented install on a Mac, enable the Finder extension, and merge two disposable folders containing a same-named file. Confirm both contents in the destination, then test removal.

## Publish the GitHub Pages guide

The illustrated guide lives in [docs/index.html](docs/index.html). In the GitHub repository, open **Settings → Pages → Build and deployment → Source** and select **GitHub Actions**. Push the source to `main`, or run **Documentation** from the Actions tab. The workflow publishes the guide and a downloadable ZIP of that exact commit. The deployment summary shows the live URL. Add that URL to the repository’s **About → Website** field so visitors can find it.

To preview the design locally, open `docs/index.html` in a browser. To test the download for the current commit, run:

```sh
git archive --format=zip --prefix=mergefolders/ -o docs/mergefolders-source.zip HEAD
```

[MIT license](LICENSE)
