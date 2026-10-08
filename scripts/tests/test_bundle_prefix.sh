#!/bin/bash
# Checks that the bundle ids and the keychain group come from BUNDLE_ID_PREFIX: the tracked default when there is
# no Local.xcconfig, and the value in Local.xcconfig when there is one. Works on a copy of this folder in a temp
# dir, so the real project, build folder and Local.xcconfig are never touched. Needs xcodegen and Xcode.
#   scripts/tests/test_bundle_prefix.sh
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
FAILS=0

rsync -a --exclude .git --exclude build --exclude .build --exclude .tools --exclude .swiftpm \
    --exclude MagMusic.xcodeproj --exclude Local.xcconfig "$ROOT/" "$TMP/work/"

setting() {   # setting <target> <name>: the build setting's value for that target
    (cd "$TMP/work" && xcodebuild -project MagMusic.xcodeproj -target "$1" -configuration Debug -showBuildSettings 2>/dev/null) \
        | sed -nE "s/^ *$2 = (.*)$/\1/p" | head -1
}

expect() {    # expect <what> <actual> <expected>
    if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: got '$2', want '$3'"; FAILS=$((FAILS + 1)); fi
}

check() {     # check <prefix>: generate the project and compare the ids with the prefix
    (cd "$TMP/work" && xcodegen generate >/dev/null)
    expect "app bundle id ($1)" "$(setting MagMusic PRODUCT_BUNDLE_IDENTIFIER)" "$1.magmusic"
    expect "widget bundle id ($1)" "$(setting MagMusicWidget PRODUCT_BUNDLE_IDENTIFIER)" "$1.magmusic.widget"
    # The app id prefix (team id and a dot) is only filled in when signing, so it is empty here.
    expect "keychain group ($1)" "$(setting MagMusic MA_KEYCHAIN_GROUP)" "$1.magmusic.shared"
}

expect "keychain group starts with the app id prefix" \
    "$(grep -c 'MA_KEYCHAIN_GROUP: $(AppIdentifierPrefix)$(BUNDLE_ID_PREFIX).magmusic.shared' "$ROOT/project.yml")" "1"

# Without Local.xcconfig: the tracked default prefix.
check local.magmusic

# With Local.xcconfig: its prefix wins, and its team is used.
printf 'DEVELOPMENT_TEAM = ABCDE12345\nBUNDLE_ID_PREFIX = org.example\n' > "$TMP/work/Local.xcconfig"
check org.example
expect "team from Local.xcconfig" "$(setting MagMusic DEVELOPMENT_TEAM)" "ABCDE12345"

[ "$FAILS" -eq 0 ] && echo "All bundle prefix checks passed." || { echo "$FAILS bundle prefix check(s) failed."; exit 1; }
