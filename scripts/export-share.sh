#!/bin/bash
# Makes the copy of MagMusic that is shared with friends: a new repository with a single commit, made from the
# committed files of share-ready (never from this repository's history, which is not for sharing).
#
#   EXPORT_AUTHOR_NAME="..." EXPORT_AUTHOR_EMAIL="..." scripts/export-share.sh [--ref <commit>] <target-dir>
#   scripts/export-share.sh --scan     only scan the files an export would contain, here, and stop
#
# Steps: refuse unless the working tree is clean and HEAD is on share-ready (or --ref names a commit); refuse
# unless the author is given and <target-dir> does not exist; unpack `git archive` (committed files minus
# export-ignore, so Local.xcconfig, .tools/, build/ and the token file cannot leak); scan with the generic
# patterns below and with the owner's own strings from an untracked patterns file (matched in any letter case;
# without that file it refuses, unless SHARE_ALLOW_NO_PATTERNS=1 is set); check that nothing refers
# to an excluded path; make the export a repository of its own, run its tests, and commit once. It never
# adds a remote and never pushes.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)
PATTERNS_FILE=${SHARE_PATTERNS_FILE:-$HOME/.config/discovery-bridge/share-patterns.txt}
EXCLUDED_PATHS=(docs/sharing)   # export-ignored; .tools/, build/ and Local.xcconfig are never committed

# Generic patterns: things that must not be in a shared copy whoever made it. Each line is
# name@@extended regex@@allowed, where matches of the allowed regex (if any) are fine.
generic_scan() {   # generic_scan <dir> <file list>: prints offending lines, returns 1 if there are any
    local dir=$1 list=$2 found=0 out
    local line name rest pattern allowed
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        name=${line%%@@*}; rest=${line#*@@}; pattern=${rest%%@@*}; allowed=${rest#*@@}
        out=$(cd "$dir" && tr '\n' '\0' < "$list" | xargs -0 grep -n -I -E -o -- "$pattern" 2>/dev/null || true)
        [ -n "$allowed" ] && out=$(printf '%s\n' "$out" | grep -v -E -- "$allowed" || true)
        if [ -n "$out" ]; then
            echo "Found $name:"; printf '%s\n' "$out" | sed 's/^/    /'
            found=1
        fi
    done <<'PATTERNS'
private IPv4 address@@(^|[^0-9.])(10\.[0-9]{1,3}|172\.(1[6-9]|2[0-9]|3[01])|192\.168)\.[0-9]{1,3}\.[0-9]{1,3}@@
MAC address@@([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}@@:(00:00:5[eE]:00:53:|02:00:00:00:00:)[0-9A-Fa-f]{2}$
email address@@[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}@@@(example\.(com|org|net)|[A-Za-z0-9.-]+\.(example|invalid|test))$
home or server path@@/(home|Users|srv)/[A-Za-z0-9._-]+@@
Spotify personal playlist id@@37i9dQZ(EVX[bc]|F1E)[A-Za-z0-9]+@@Fake
provider instance id@@[a-z_]+--[A-Za-z0-9]+@@--test[0-9]*$
sp_dc cookie@@sp_dc=[A-Za-z0-9%]{8,}@@
bearer token@@[Bb]earer [A-Za-z0-9._~+/-]{20,}@@
JSON web token@@eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}@@
PATTERNS
    return $found
}

owner_scan() {   # owner_scan <dir> <file list>: the owner's literal strings, from a file outside the repository
    local dir=$1 list=$2 out
    if [ ! -f "$PATTERNS_FILE" ]; then
        if [ "${SHARE_ALLOW_NO_PATTERNS:-}" = "1" ]; then
            echo "WARNING: no owner patterns file at $PATTERNS_FILE; SHARE_ALLOW_NO_PATTERNS=1 is set, so only"
            echo "WARNING: the generic scan ran."
            return 0
        fi
        echo "No owner patterns file at $PATTERNS_FILE. Put your strings there, one per line (hostname, user"
        echo "name, account and provider ids, email, LAN subnet), or set SHARE_ALLOW_NO_PATTERNS=1 to rely on"
        echo "the generic scan only."
        return 1
    fi
    out=$(cd "$dir" && tr '\n' '\0' < "$list" | xargs -0 grep -n -I -i -F -f <(grep -v -E '^[[:space:]]*(#|$)' "$PATTERNS_FILE") 2>/dev/null || true)
    if [ -n "$out" ]; then
        echo "Found the owner's own strings (shown by file and line only):"
        printf '%s\n' "$out" | cut -d: -f1,2 | sed 's/^/    /'
        return 1
    fi
}

reference_scan() {   # reference_scan <dir> <file list>: references to paths the export leaves out
    local dir=$1 list=$2 found=0 out p
    for p in "${EXCLUDED_PATHS[@]}"; do
        out=$(cd "$dir" && tr '\n' '\0' < "$list" | xargs -0 grep -n -I -F -- "$p" 2>/dev/null | grep -v -E '^(\.gitignore|\.gitattributes|scripts/export-share\.sh):' || true)
        if [ -n "$out" ]; then echo "Found a reference to the excluded $p:"; printf '%s\n' "$out" | sed 's/^/    /'; found=1; fi
    done
    return $found
}

tracked_for_export() {   # the tracked files an export would contain: everything not marked export-ignore
    git ls-files | git check-attr --stdin export-ignore | sed -n 's/: export-ignore: unspecified$//p'
}

if [ "${1:-}" = "--scan" ]; then
    LIST=$(mktemp); trap 'rm -f "$LIST"' EXIT
    tracked_for_export > "$LIST"
    status=0
    generic_scan "$ROOT" "$LIST" || status=1
    owner_scan "$ROOT" "$LIST" || status=1
    [ "$status" -eq 0 ] && echo "Scan clean: $(wc -l < "$LIST" | tr -d ' ') files." || echo "Scan found problems."
    exit $status
fi

REF=""
if [ "${1:-}" = "--ref" ]; then REF=${2:?--ref needs a commit}; shift 2; fi
TARGET=${1:?usage: scripts/export-share.sh [--ref <commit>] <target-dir>}

[ -z "$(git status --porcelain)" ] || { echo "The working tree is not clean; commit or stash first."; exit 1; }
if [ -z "$REF" ]; then
    [ "$(git rev-parse --abbrev-ref HEAD)" = "share-ready" ] || { echo "HEAD is not on share-ready (or pass --ref)."; exit 1; }
    REF=HEAD
fi
git rev-parse --verify --quiet "$REF^{commit}" >/dev/null || { echo "Not a commit: $REF"; exit 1; }
: "${EXPORT_AUTHOR_NAME:?set EXPORT_AUTHOR_NAME (the author of the single commit of the export)}"
: "${EXPORT_AUTHOR_EMAIL:?set EXPORT_AUTHOR_EMAIL}"
[ ! -e "$TARGET" ] || { echo "$TARGET exists already; pick a new folder."; exit 1; }
[ -f "$PATTERNS_FILE" ] || [ "${SHARE_ALLOW_NO_PATTERNS:-}" = "1" ] || {
    echo "No owner patterns file at $PATTERNS_FILE; create it, or set SHARE_ALLOW_NO_PATTERNS=1."; exit 1; }

mkdir -p "$TARGET"
TARGET=$(cd "$TARGET" && pwd)
git archive --format=tar "$REF" | tar -x -C "$TARGET"
find "$TARGET" -mindepth 1 -type d -empty -delete   # folders whose files were all export-ignored
echo "Exported $(git rev-parse --short "$REF") into $TARGET"

LIST=$(mktemp); trap 'rm -f "$LIST"' EXIT
(cd "$TARGET" && find . -type f | sed 's|^\./||') > "$LIST"
status=0
generic_scan "$TARGET" "$LIST" || status=1
owner_scan "$TARGET" "$LIST" || status=1
reference_scan "$TARGET" "$LIST" || status=1
[ "$status" -eq 0 ] || { echo "The export is not clean; it stays in $TARGET for a look, uncommitted."; exit 1; }
echo "Scans clean."

cd "$TARGET"
git init -q -b main
git add -A
echo "Running the tests in the export"
TEST_LOG=$(mktemp -t magmusic-export-tests)
(cd MAKit && swift test) > "$TEST_LOG" 2>&1 || { echo "swift test failed in the export; see $TEST_LOG"; exit 1; }
scripts/tests/test_install_xcconfig.sh >/dev/null || { echo "test_install_xcconfig.sh failed in the export"; exit 1; }
scripts/tests/test_export_share.sh >/dev/null || { echo "test_export_share.sh failed in the export"; exit 1; }
if command -v xcodegen >/dev/null; then
    scripts/tests/test_bundle_prefix.sh >/dev/null || { echo "test_bundle_prefix.sh failed in the export"; exit 1; }
fi
rm -rf MAKit/.build
git -c user.name="$EXPORT_AUTHOR_NAME" -c user.email="$EXPORT_AUTHOR_EMAIL" commit -q -m "MagMusic"
echo "Done: $TARGET has one commit by $EXPORT_AUTHOR_NAME. No remote was added; nothing was pushed."
