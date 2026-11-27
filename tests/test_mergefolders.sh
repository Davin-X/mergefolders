#!/usr/bin/env bash
# Tests for the mergefolders script. Run: bash tests/test_mergefolders.sh
set -u
here=$(cd -- "$(dirname -- "$0")" && pwd)
script="$here/../mergefolders"
pass=0
fail=0

assert_contains() {
  if printf '%s' "$2" | grep -qF -- "$3"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL: %s\n  output was missing: %s\n' "$1" "$3"
  fi
}

tmp=$(mktemp -d) || exit 1
trap 'rm -rf -- "$tmp"' EXIT
export MERGEFOLDERS_LOG_DIR="$tmp/logs"  # keep undo logs out of ~/Library

# Hidden multi-dot file: ".config.json" -> ".config (2).json"
mkdir -p "$tmp/src" "$tmp/dest"
printf x > "$tmp/src/.config.json"
printf y > "$tmp/dest/.config.json"
out=$(bash "$script" --dry-run --to "$tmp/dest" "$tmp/src" 2>&1)
assert_contains "hidden multi-dot rename" "$out" ".config (2).json"

# Hidden file without inner extension: ".env" -> ".env (2)"
rm -rf "$tmp/dest"; mkdir -p "$tmp/dest"
printf x > "$tmp/src/.env"; printf y > "$tmp/dest/.env"
out=$(bash "$script" --dry-run --to "$tmp/dest" "$tmp/src" 2>&1)
assert_contains "hidden file rename" "$out" ".env (2)"

# Visible file keeps its extension: "photo.jpg" -> "photo (2).jpg"
rm -rf "$tmp/dest"; mkdir -p "$tmp/dest"
printf x > "$tmp/src/photo.jpg"; printf y > "$tmp/dest/photo.jpg"
out=$(bash "$script" --dry-run --to "$tmp/dest" "$tmp/src" 2>&1)
assert_contains "file rename keeps ext" "$out" "photo (2).jpg"

# Extension-less file: "noext" -> "noext (2)"
rm -rf "$tmp/dest"; mkdir -p "$tmp/dest"
printf x > "$tmp/src/noext"; printf y > "$tmp/dest/noext"
out=$(bash "$script" --dry-run --to "$tmp/dest" "$tmp/src" 2>&1)
assert_contains "no-ext rename" "$out" "noext (2)"

# Sibling with a shared prefix is not treated as inside the source.
mkdir -p "$tmp/Photos" "$tmp/Photos2"
if out=$(bash "$script" --dry-run --to "$tmp/Photos2" "$tmp/Photos" 2>&1); then
  pass=$((pass + 1))
else
  fail=$((fail + 1)); echo "FAIL: sibling prefix rejected"
fi

mkdir "$tmp/Photos/sub"
if out=$(bash "$script" --to "$tmp/Photos/sub" "$tmp/Photos" 2>&1); then
  fail=$((fail + 1)); echo "FAIL: inside-destination not refused"
else
  assert_contains "nested destination rejected" "$out" "destination is inside"
fi

# Exercise real moves and check both copies after a collision.
mkdir -p "$tmp/first/sub" "$tmp/second/sub" "$tmp/result"
printf first > "$tmp/first/sub/photo.jpg"
printf second > "$tmp/second/sub/photo.jpg"
"$script" --to "$tmp/result" "$tmp/first" "$tmp/second" || exit 1
[[ $(cat "$tmp/result/sub/photo.jpg") = first &&
   $(cat "$tmp/result/sub/photo (2).jpg") = second &&
   ! -e "$tmp/first" && ! -e "$tmp/second" ]] || exit 1
pass=$((pass + 1))

mkdir "$tmp/original"
touch "$tmp/original/untouched"
ln -s "$tmp/original" "$tmp/shortcut"
"$script" --to "$tmp/result" "$tmp/shortcut/" || exit 1
[[ -L "$tmp/result/shortcut" && -f "$tmp/original/untouched" ]] || exit 1
pass=$((pass + 1))

mkdir -p "$tmp/linked/sub" "$tmp/result2"
touch "$tmp/linked/sub/file"
ln -s "$tmp/original" "$tmp/result2/sub"
if "$script" --to "$tmp/result2" "$tmp/linked"; then exit 1; fi
[[ -f "$tmp/linked/sub/file" && ! -e "$tmp/original/file" ]] || exit 1
pass=$((pass + 1))

# A stub prevents traversal even if the root guard regresses.
mkdir "$tmp/bin"
cat > "$tmp/bin/find" <<'STUB'
#!/bin/bash
printf '%s\0' "$1/partial"
exit 1
STUB
chmod +x "$tmp/bin/find"
if out=$(PATH="$tmp/bin:$PATH" "$script" --dry-run --to "$tmp/result" / 2>&1); then exit 1; fi
assert_contains "root guard" "$out" "filesystem root"
mkdir "$tmp/incomplete"
touch "$tmp/incomplete/partial"
if PATH="$tmp/bin:$PATH" "$script" --to "$tmp/result" "$tmp/incomplete"; then exit 1; fi
[[ -f "$tmp/incomplete/partial" && ! -e "$tmp/result/partial" ]] || exit 1
pass=$((pass + 1))

# Exercise the actual picker error handler without opening a dialog.
cat > "$tmp/bin/osascript" <<'STUB'
#!/bin/bash
sed "s/return POSIX path of (choose folder.*)/error \"picker test\" number $PICKER_ERROR/" | /usr/bin/osascript
STUB
chmod +x "$tmp/bin/osascript"
if ! out=$(PATH="$tmp/bin:$PATH" PICKER_ERROR=-128 "$script" --notify "$tmp/incomplete" 2>&1); then exit 1; fi
[[ -z "$out" && -f "$tmp/incomplete/partial" ]] || exit 1
pass=$((pass + 1))
if out=$(PATH="$tmp/bin:$PATH" PICKER_ERROR=-1708 "$script" "$tmp/incomplete" 2>&1); then exit 1; fi
assert_contains "picker failure remains visible" "$out" "picker test"

# A lock left behind by a killed merge is taken over, a live one is not.
lock_dir() { (cd -P -- "$1" && printf '%s' "${TMPDIR:-/tmp}/mergefolders-lock-$(printf '%s' "$PWD" | shasum -a 256 | cut -c1-16)"); }
mkdir -p "$tmp/stale" "$tmp/staleout"
printf x > "$tmp/stale/file"
lock=$(lock_dir "$tmp/staleout")
mkdir -p "$lock"
printf 999999 > "$lock/pid"
"$script" --to "$tmp/staleout" "$tmp/stale" || exit 1
[[ -f "$tmp/staleout/file" ]] || exit 1
pass=$((pass + 1))

mkdir -p "$tmp/busy" "$tmp/busyout"
printf x > "$tmp/busy/file"
lock=$(lock_dir "$tmp/busyout")
mkdir -p "$lock"
sleep 30 & holder=$!
printf '%s' "$holder" > "$lock/pid"
if out=$("$script" --to "$tmp/busyout" "$tmp/busy" 2>&1); then exit 1; fi
kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null
rm -rf -- "$lock"
assert_contains "live lock still refuses" "$out" "already running"
[[ -f "$tmp/busy/file" && ! -e "$tmp/busyout/file" ]] || exit 1
pass=$((pass + 1))

# Concurrent test: two merges to same destination should serialize, not corrupt.
mkdir -p "$tmp/conc1/sub" "$tmp/conc2/sub" "$tmp/conc_out"
printf a > "$tmp/conc1/sub/file"
printf b > "$tmp/conc2/sub/file"
"$script" --to "$tmp/conc_out" "$tmp/conc1" "$tmp/conc2" &
p1=$!
"$script" --to "$tmp/conc_out" "$tmp/conc1" "$tmp/conc2" &
p2=$!
wait "$p1" "$p2"
# Both should succeed (one after the other); dest has both files with (2) suffix
[[ -f "$tmp/conc_out/sub/file" && -f "$tmp/conc_out/sub/file (2)" ]] || exit 1
pass=$((pass + 1))

# --version matches the single version source.
out=$("$script" --version)
assert_contains "version flag" "$out" "mergefolders $(sed -n 's/^VERSION=//p' "$script")"

# Preview sees collisions between sources, not only with existing files.
mkdir -p "$tmp/pa" "$tmp/pb" "$tmp/pout"
printf a > "$tmp/pa/note.txt"; printf b > "$tmp/pb/note.txt"
out=$("$script" --dry-run --to "$tmp/pout" "$tmp/pa" "$tmp/pb")
assert_contains "preview cross-source rename" "$out" "pout/note (2).txt"
[[ -f "$tmp/pa/note.txt" && -f "$tmp/pb/note.txt" ]] || exit 1

# Undo puts every file back, removes folders the merge created, keeps old content.
rm -rf "$tmp/logs"
mkdir -p "$tmp/ua/deep/er" "$tmp/ub" "$tmp/uout"
printf a > "$tmp/ua/deep/er/f.txt"; printf b > "$tmp/ub/f.txt"; printf old > "$tmp/uout/f.txt"
(cd "$tmp" && "$script" --to uout ua ub/f.txt) || exit 1
[[ -f "$tmp/uout/f (2).txt" && -f "$tmp/uout/deep/er/f.txt" && ! -e "$tmp/ua" ]] || exit 1
out=$("$script" --undo) || exit 1
assert_contains "undo summary" "$out" "restored 2 · failed 0"
[[ $(cat "$tmp/ua/deep/er/f.txt") = a && $(cat "$tmp/ub/f.txt") = b &&
   $(cat "$tmp/uout/f.txt") = old && ! -e "$tmp/uout/deep" && ! -e "$tmp/uout/f (2).txt" ]] || exit 1
pass=$((pass + 1))
if out=$("$script" --undo 2>&1); then exit 1; fi
assert_contains "nothing left to undo" "$out" "no merge to undo"
if out=$("$script" --undo --dry-run 2>&1); then exit 1; fi
assert_contains "undo refuses dry-run" "$out" "takes only an undo log"

# An explicit log undoes that merge, not a later one; a used log is refused.
mkdir -p "$tmp/ea" "$tmp/eb" "$tmp/eout"
printf a > "$tmp/ea/one"; printf b > "$tmp/eb/two"
log=$("$script" --to "$tmp/eout" "$tmp/ea" | sed -n 's/^undo log: //p')
"$script" --to "$tmp/eout" "$tmp/eb" >/dev/null || exit 1
"$script" --undo "$log" >/dev/null || exit 1
[[ -f "$tmp/ea/one" && -f "$tmp/eout/two" ]] || exit 1
pass=$((pass + 1))
if out=$("$script" --undo "$log" 2>&1); then exit 1; fi
assert_contains "used log refused" "$out" "already undone"

# Undo reports a file that is gone instead of guessing.
mkdir -p "$tmp/ga" "$tmp/gout"
printf a > "$tmp/ga/x"; printf a > "$tmp/ga/y"
"$script" --to "$tmp/gout" "$tmp/ga" || exit 1
rm "$tmp/gout/x"
if out=$("$script" --undo 2>&1); then exit 1; fi
assert_contains "undo reports missing" "$out" "restored 1 · failed 1"

# A source that cannot be listed is skipped; the next source still merges.
mkdir -p "$tmp/okay" "$tmp/skipout"
printf x > "$tmp/okay/kept"
cat > "$tmp/bin/find" <<'STUB'
#!/bin/bash
case $1 in */incomplete) printf '%s\0' "$1/partial"; exit 1 ;; esac
exec /usr/bin/find "$@"
STUB
if out=$(PATH="$tmp/bin:$PATH" "$script" --to "$tmp/skipout" "$tmp/incomplete" "$tmp/okay" 2>&1); then exit 1; fi
assert_contains "listing failure is reported" "$out" "left it untouched"
[[ -f "$tmp/incomplete/partial" && -f "$tmp/skipout/kept" ]] || exit 1
pass=$((pass + 1))

# A failed undo item stays in the log, so the same undo can retry it.
mkdir -p "$tmp/ra" "$tmp/rout"
printf a > "$tmp/ra/k"; printf b > "$tmp/ra/m"
log=$("$script" --to "$tmp/rout" "$tmp/ra" | sed -n 's/^undo log: //p')
mkdir -p "$tmp/ra"; printf taken > "$tmp/ra/k"
if out=$("$script" --undo "$log" 2>&1); then exit 1; fi
assert_contains "partial undo" "$out" "restored 1 · failed 1"
rm "$tmp/ra/k"
out=$("$script" --undo "$log") || exit 1
assert_contains "undo retry" "$out" "restored 1 · failed 0"
[[ $(cat "$tmp/ra/k") = a && $(cat "$tmp/ra/m") = b && -f "$log.undone" ]] || exit 1
pass=$((pass + 1))

# Empty folders move with the merge and come back on undo.
mkdir -p "$tmp/fa/Drafts" "$tmp/fa/Same" "$tmp/fout/Same"
log=$("$script" --to "$tmp/fout" "$tmp/fa" | sed -n 's/^undo log: //p')
[[ -d "$tmp/fout/Drafts" && ! -e "$tmp/fout/Same (2)" && ! -e "$tmp/fa" ]] || exit 1
"$script" --undo "$log" >/dev/null || exit 1
[[ -d "$tmp/fa/Drafts" && ! -e "$tmp/fout/Drafts" && -d "$tmp/fout/Same" ]] || exit 1
pass=$((pass + 1))

# Cancel (SIGTERM) lets the running move finish and logs it, so undo restores everything.
mkdir -p "$tmp/ca/zz-empty" "$tmp/cout"
for i in 1 2 3 4 5; do printf %s "$i" > "$tmp/ca/f$i"; done
cat > "$tmp/bin/mv" <<'STUB'
#!/bin/bash
/bin/sleep 0.3; exec /bin/mv "$@"
STUB
chmod +x "$tmp/bin/mv"
PATH="$tmp/bin:$PATH" "$script" --to "$tmp/cout" "$tmp/ca" > "$tmp/cancel.out" 2>&1 & cpid=$!
/bin/sleep 0.45; kill -TERM "$cpid"; wait "$cpid"; status=$?
rm "$tmp/bin/mv"
[[ $status -eq 130 && -f "$tmp/ca/f5" ]] || { echo "FAIL: cancel stopped early (status $status)"; exit 1; }
log=$(sed -n 's/^undo log: //p' "$tmp/cancel.out")
out=$("$script" --undo "$log") || exit 1
assert_contains "undo after cancel" "$out" "failed 0"
[[ $(find "$tmp/ca" -type f | wc -l) -eq 5 && -d "$tmp/ca/zz-empty" && -z $(find "$tmp/cout" -mindepth 1) ]] || { echo "FAIL: cancel left files behind"; exit 1; }
pass=$((pass + 1))

printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
