#!/bin/bash
# Tests the owner patterns check of export-share.sh with --scan, in a throwaway git repository in a temp dir:
# nothing is exported and this repository is not touched.
#   scripts/tests/test_export_share.sh
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
FAILS=0

expect() {    # expect <what> <actual> <expected>
    if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: got '$2', want '$3'"; FAILS=$((FAILS + 1)); fi
}

REPO="$TMP/repo"
mkdir -p "$REPO/scripts"
cp "$ROOT/scripts/export-share.sh" "$REPO/scripts/"
printf 'built on myserver\n' > "$REPO/notes.md"
git -C "$REPO" init -q -b share-ready
git -C "$REPO" add -A
git -C "$REPO" -c user.name=t -c user.email=t@example.org -c commit.gpgsign=false commit -q -m start

scan() {      # scan [VAR=value ...]: runs --scan with only the given variables set; prints the exit code
    local status=0
    env -u SHARE_ALLOW_NO_PATTERNS -u SHARE_PATTERNS_FILE "$@" "$REPO/scripts/export-share.sh" --scan \
        > "$TMP/out" 2>&1 || status=$?
    echo "$status"
}

# 1. Without the patterns file the scan is refused.
expect "missing patterns file is refused" "$(scan SHARE_PATTERNS_FILE="$TMP/none.txt")" "1"
expect "refusal names the override" "$(grep -c SHARE_ALLOW_NO_PATTERNS "$TMP/out")" "1"

# 2. SHARE_ALLOW_NO_PATTERNS=1 lets it run with the generic scan only.
expect "override allows the scan" "$(scan SHARE_PATTERNS_FILE="$TMP/none.txt" SHARE_ALLOW_NO_PATTERNS=1)" "0"

# 3. An empty patterns file finds nothing.
: > "$TMP/empty.txt"
expect "empty patterns file is clean" "$(scan SHARE_PATTERNS_FILE="$TMP/empty.txt")" "0"

# 4. A pattern matches in any letter case, and the matched text is never printed.
printf '# my strings\nMyServer\n' > "$TMP/patterns.txt"
expect "pattern in another letter case is found" "$(scan SHARE_PATTERNS_FILE="$TMP/patterns.txt")" "1"
expect "finding names the file and line" "$(grep -c 'notes.md:1' "$TMP/out")" "1"
expect "matched text is not printed" "$(grep -ci myserver "$TMP/out" || true)" "0"

if [ "$FAILS" -eq 0 ]; then echo "All passed."; else echo "$FAILS failed."; exit 1; fi
