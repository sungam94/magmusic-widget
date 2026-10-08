#!/bin/bash
# Helpers for scripts/install.sh, kept apart so scripts/tests/test_install_xcconfig.sh can test them without
# building or installing anything. Sourced, not run.

# installed_prefix <app>: the bundle id prefix of an installed MagMusic.app, that is its CFBundleIdentifier
# without ".magmusic". Prints nothing when there is no such app or it is not MagMusic.
installed_prefix() {
    local id
    id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$1/Contents/Info.plist" 2>/dev/null) || return 0
    case "$id" in
        ?*.magmusic) printf '%s\n' "${id%.magmusic}" ;;
    esac
}

# write_local_xcconfig <file> <team> <installed app> [ask]: writes the signing team into Local.xcconfig and
# prints the bundle id prefix. Only the DEVELOPMENT_TEAM line is replaced; every other line stays as it is. A
# missing BUNDLE_ID_PREFIX is taken from the installed app (so a rebuild keeps the bundle id, the keychain group
# and with them the saved token and the widget), else asked for when the fourth argument is "ask", with
# local.<team in lower case> as the default, and is written.
write_local_xcconfig() {
    local file=$1 team=$2 app=$3 ask=${4:-} tmp prefix
    tmp=$(mktemp)
    if [ -f "$file" ]; then
        awk -v team="$team" '
            /^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=/ { if (!done) print "DEVELOPMENT_TEAM = " team; done = 1; next }
            { print }
            END { if (!done) print "DEVELOPMENT_TEAM = " team }
        ' "$file" > "$tmp"
    else
        printf '// Local signing settings (not committed): your Apple ID team and your bundle id prefix.\n' > "$tmp"
        printf 'DEVELOPMENT_TEAM = %s\n' "$team" >> "$tmp"
    fi
    prefix=$(sed -nE 's/^[[:space:]]*BUNDLE_ID_PREFIX[[:space:]]*=[[:space:]]*([^[:space:]]+).*/\1/p' "$tmp" | tail -1)
    if [ -z "$prefix" ]; then
        prefix=$(installed_prefix "$app")
        if [ -z "$prefix" ]; then
            prefix="local.$(printf '%s' "$team" | tr '[:upper:]' '[:lower:]')"
            [ "$ask" = ask ] && prefix=$(ask_prefix "$prefix")
        fi
        printf 'BUNDLE_ID_PREFIX = %s\n' "$prefix" >> "$tmp"
    fi
    mv "$tmp" "$file"
    printf '%s\n' "$prefix"
}

# ask_prefix <default>: asks for a bundle id prefix until the answer looks like reverse DNS (org.example); an
# empty answer or none at all gives the default. Prints the prefix.
ask_prefix() {
    local answer
    echo "Bundle id prefix: a reverse-DNS name of yours, for example org.example. The app becomes" >&2
    echo "<prefix>.magmusic. Changing it later makes a new app (token and widget set up again)." >&2
    while true; do
        printf 'Bundle id prefix [%s]: ' "$1" >&2
        read -r answer || answer=""
        [ -n "$answer" ] || { printf '%s\n' "$1"; return 0; }
        if printf '%s' "$answer" | grep -q -E '^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$'; then
            printf '%s\n' "$answer"; return 0
        fi
        echo "Letters, digits and hyphens in at least two parts separated by dots, for example org.example." >&2
    done
}

# ask_server: prints the Music Assistant address. MA_URL when it is set, else asked on the terminal until the
# answer starts with http:// or https://. There is no default; without an answer it fails.
ask_server() {
    local url=${MA_URL:-}
    while true; do
        if [ -z "$url" ]; then
            printf 'Music Assistant server, for example http://<server-ip>:8095: ' >&2
            read -r url || return 1
        fi
        case "$url" in
            http://?* | https://?*) printf '%s\n' "$url"; return 0 ;;
        esac
        [ -n "$url" ] && echo "The address starts with http:// or https://, for example http://<server-ip>:8095." >&2
        url=""
    done
}
