#!/bin/bash
# Tests the helpers install.sh uses for Local.xcconfig and the server address, in a temp dir: nothing is built,
# installed or read from /Applications.
#   scripts/tests/test_install_xcconfig.sh
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
# shellcheck source=../install_lib.sh
source "$ROOT/scripts/install_lib.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
FAILS=0

expect() {    # expect <what> <actual> <expected>
    if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: got '$2', want '$3'"; FAILS=$((FAILS + 1)); fi
}

fake_app() {  # fake_app <dir> <bundle id>: an app folder with just an Info.plist
    mkdir -p "$1/Contents"
    /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $2" "$1/Contents/Info.plist" >/dev/null
}

value() { sed -nE "s/^[[:space:]]*$2[[:space:]]*=[[:space:]]*([^[:space:]]+).*/\1/p" "$1"; }

# 1. An existing BUNDLE_ID_PREFIX survives a rewrite; only the team line changes, every other line stays.
F="$TMP/one.xcconfig"
printf '// my notes\nDEVELOPMENT_TEAM = OLDTEAM123\nBUNDLE_ID_PREFIX = org.mine\nOTHER_SETTING = 1\n' > "$F"
fake_app "$TMP/Other.app" org.someone.magmusic
expect "kept prefix is printed" "$(write_local_xcconfig "$F" NEWTEAM456 "$TMP/Other.app")" "org.mine"
expect "kept prefix" "$(value "$F" BUNDLE_ID_PREFIX)" "org.mine"
expect "new team" "$(value "$F" DEVELOPMENT_TEAM)" "NEWTEAM456"
expect "one team line" "$(grep -c DEVELOPMENT_TEAM "$F")" "1"
expect "other lines kept in order" "$(grep -v DEVELOPMENT_TEAM "$F" | tr '\n' '|')" "// my notes|BUNDLE_ID_PREFIX = org.mine|OTHER_SETTING = 1|"
expect "team line stays in its place" "$(sed -n 2p "$F")" "DEVELOPMENT_TEAM = NEWTEAM456"

# 2. A missing prefix is taken from the installed app's bundle id, without ".magmusic".
F="$TMP/two.xcconfig"
printf 'DEVELOPMENT_TEAM = OLDTEAM123\n' > "$F"
fake_app "$TMP/Installed.app" org.friend.magmusic
expect "prefix from the installed app is printed" "$(write_local_xcconfig "$F" ABCDE12345 "$TMP/Installed.app")" "org.friend"
expect "prefix from the installed app" "$(value "$F" BUNDLE_ID_PREFIX)" "org.friend"
expect "team" "$(value "$F" DEVELOPMENT_TEAM)" "ABCDE12345"
expect "installed_prefix of an app with another id" "$(installed_prefix "$TMP/Other.app")" "org.someone"
fake_app "$TMP/Foreign.app" org.example.something
expect "installed_prefix of an app that is not MagMusic" "$(installed_prefix "$TMP/Foreign.app")" ""

# 3. A fresh setup (no file, no installed app) gets local.<team in lower case>.
F="$TMP/three.xcconfig"
expect "fresh prefix is printed" "$(write_local_xcconfig "$F" ABCDE12345 "$TMP/Missing.app")" "local.abcde12345"
expect "fresh prefix" "$(value "$F" BUNDLE_ID_PREFIX)" "local.abcde12345"
expect "fresh team" "$(value "$F" DEVELOPMENT_TEAM)" "ABCDE12345"
write_local_xcconfig "$F" ABCDE12345 "$TMP/Installed.app" >/dev/null
expect "a second run keeps the written prefix" "$(value "$F" BUNDLE_ID_PREFIX)" "local.abcde12345"

# 3b. On a fresh interactive install the prefix is asked for, with local.<team> as the default; only then.
F="$TMP/ask1.xcconfig"
expect "asked prefix" "$(printf 'org.friend\n' | write_local_xcconfig "$F" ABCDE12345 "$TMP/Missing.app" ask 2>/dev/null)" "org.friend"
expect "asked prefix written" "$(value "$F" BUNDLE_ID_PREFIX)" "org.friend"
F="$TMP/ask2.xcconfig"
expect "empty answer takes the default" "$(printf '\n' | write_local_xcconfig "$F" ABCDE12345 "$TMP/Missing.app" ask 2>/dev/null)" "local.abcde12345"
F="$TMP/ask3.xcconfig"
expect "asked again until reverse-DNS" \
    "$(printf 'no spaces please\nsingle\norg.friend-2\n' | write_local_xcconfig "$F" ABCDE12345 "$TMP/Missing.app" ask 2>/dev/null)" "org.friend-2"
F="$TMP/ask4.xcconfig"
expect "no answer takes the default" "$(write_local_xcconfig "$F" ABCDE12345 "$TMP/Missing.app" ask </dev/null 2>/dev/null)" "local.abcde12345"
F="$TMP/ask5.xcconfig"
expect "an installed app is not asked about" \
    "$(printf 'org.other\n' | write_local_xcconfig "$F" ABCDE12345 "$TMP/Installed.app" ask 2>/dev/null)" "org.friend"
F="$TMP/ask6.xcconfig"
printf 'BUNDLE_ID_PREFIX = org.mine\n' > "$F"
expect "a written prefix is not asked about" \
    "$(printf 'org.other\n' | write_local_xcconfig "$F" ABCDE12345 "$TMP/Missing.app" ask 2>/dev/null)" "org.mine"

# 4. The server address: MA_URL when set, else asked until it starts with http:// or https://; no default.
expect "MA_URL is used" "$(MA_URL=http://ma.example:8095 ask_server </dev/null 2>/dev/null)" "http://ma.example:8095"
expect "asked again while empty or without a scheme" \
    "$(printf '\nma.example:8095\nhttps://ma.example:8095\n' | MA_URL= ask_server 2>/dev/null)" "https://ma.example:8095"
expect "no answer is a failure, not a default" "$( (MA_URL= ask_server </dev/null 2>/dev/null && echo ok) || echo failed)" "failed"
expect "the prompt shows an example, not an address" \
    "$(printf 'http://x:8095\n' | MA_URL= ask_server 2>&1 >/dev/null | grep -c 'http://<server-ip>:8095')" "1"

[ "$FAILS" -eq 0 ] && echo "All install.sh helper checks passed." || { echo "$FAILS install.sh helper check(s) failed."; exit 1; }
