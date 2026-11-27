#!/usr/bin/env bash
set -euo pipefail

here=$(cd -- "$(dirname -- "$0")" && pwd)
case "${1-}" in
  --cli-only) ;;
  "")
    bash "$here/finder/build.sh"
    workflow="$HOME/Library/Services/Merge Folders.workflow/Contents/document.wflow"
    if [ -f "$workflow" ] && ! plutil -extract actions.1 xml1 -o /dev/null "$workflow" 2>/dev/null; then
      command=$(plutil -extract actions.0.action.ActionParameters.COMMAND_STRING raw -o - "$workflow" 2>/dev/null || true)
      case "$command" in
        'exec "$HOME/bin/mergefolders" --notify "$@"'|'exec /usr/bin/open -n -a /Applications/MergeFolders.app --args --merge "$@"')
          retired=$(mktemp -d "$HOME/.Trash/MergeFolders-XXXXXX")
          mv "$HOME/Library/Services/Merge Folders.workflow" "$retired/"
          echo "Moved the old Merge Folders Quick Action to the Trash."
          ;;
      esac
    fi
    ;;
  *) echo "usage: $0 [--cli-only]" >&2; exit 2 ;;
esac

mkdir -p "$HOME/bin"
install -m 755 "$here/mergefolders" "$HOME/bin/mergefolders"
echo "Installed the CLI. Run ~/bin/mergefolders --help to get started."
