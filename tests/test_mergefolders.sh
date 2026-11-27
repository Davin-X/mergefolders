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

if out=$(bash "$script" --to "$tmp/Photos/sub" "$tmp/Photos" 2>&1); then
  fail=$((fail + 1)); echo "FAIL: inside-destination not refused"
else
  pass=$((pass + 1))
fi

printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
