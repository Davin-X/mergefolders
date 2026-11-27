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

printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
