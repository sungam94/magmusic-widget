#!/bin/bash
# Builds MagMusic, signs it with this Mac's free Apple ID team, installs it in /Applications and keeps it
# working: a free team's signing expires after 7 days, so a weekly LaunchAgent rebuilds it.
#   scripts/install.sh            build, install, ask for the MA token if none is set, add the weekly rebuild
#   scripts/install.sh --rebuild  build and install only (what the weekly job runs)
#   scripts/install.sh --token    ask for the server and token again
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)
# shellcheck source=install_lib.sh
source "$ROOT/scripts/install_lib.sh"
MODE=${1:-install}
APP=/Applications/MagMusic.app
LOG=~/Library/Logs/MagMusic-rebuild.log
say() { printf '\n==> %s\n' "$*"; }

# xcode-select may still point at the Command Line Tools; use Xcode.app from /Applications for this script.
if ! xcodebuild -version >/dev/null 2>&1; then
    XCODE=$(ls -d /Applications/Xcode*.app 2>/dev/null | head -1)
    [ -n "$XCODE" ] && export DEVELOPER_DIR="$XCODE/Contents/Developer"
fi
if ! OUT=$(xcodebuild -version 2>&1); then
    echo "xcodebuild does not run:"; echo "$OUT" | tail -3
    case "$OUT" in
        *license*) echo "Accept the Xcode license: open Xcode once, or run: sudo xcodebuild -license accept" ;;
        *) echo "Install Xcode from the App Store, open it once (let it install its components), then run this again." ;;
    esac
    exit 1
fi
# XcodeGen: from Homebrew when there is one, else the release from GitHub, kept next to the project.
LOCAL_XCODEGEN="$ROOT/.tools/xcodegen/bin/xcodegen"
if ! command -v xcodegen >/dev/null; then
    if [ -x "$LOCAL_XCODEGEN" ]; then
        :
    elif command -v brew >/dev/null; then
        say "Installing XcodeGen (Homebrew)"
        brew install xcodegen
    else
        say "Fetching XcodeGen from GitHub"
        mkdir -p "$ROOT/.tools"
        curl -sfL -o "$ROOT/.tools/xcodegen.zip" https://github.com/yonaskolb/XcodeGen/releases/latest/download/xcodegen.zip
        unzip -q -o "$ROOT/.tools/xcodegen.zip" -d "$ROOT/.tools"
        rm "$ROOT/.tools/xcodegen.zip"
    fi
fi
command -v xcodegen >/dev/null || PATH="$(dirname "$LOCAL_XCODEGEN"):$PATH"

# The certificate: Xcode creates it; it only counts as valid with Apple's WWDR G3 intermediate in the keychain.
if ! security find-identity -p codesigning | grep -q "Apple Development"; then
    echo "No signing certificate yet. In Xcode: Settings → Accounts → + (your Apple ID) → Manage Certificates… → + → Apple Development."
    exit 1
fi
if ! security find-identity -v -p codesigning | grep -q "Apple Development"; then
    say "Adding Apple's WWDR G3 intermediate certificate"
    TMP=$(mktemp -d)
    curl -sfL -o "$TMP/wwdr.cer" https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer
    security import "$TMP/wwdr.cer" -k ~/Library/Keychains/login.keychain-db >/dev/null
fi
TEAM=$(security find-certificate -c "Apple Development" -p | openssl x509 -noout -subject | sed -nE 's/.*OU ?= ?([A-Z0-9]{10}).*/\1/p')
[ -n "$TEAM" ] || { echo "Could not read the team from the certificate."; exit 1; }
# Local.xcconfig: the team, and the bundle id prefix (kept if set, else taken from the installed app, else
# asked for on a first install at a terminal, with local.<team> as the default). The order matters: this reads
# the installed app's bundle id, so it runs before the build and before the old app is removed below. Keeping
# the installed prefix keeps the keychain group, the saved token and the widget.
ASK=""
[ "$MODE" != "--rebuild" ] && [ -t 0 ] && ASK=ask
PREFIX=$(write_local_xcconfig Local.xcconfig "$TEAM" "$APP" "$ASK")

# Over SSH the login keychain is locked and signing fails with errSecInternalComponent: unlock it first.
if [ -n "${SSH_CONNECTION:-}" ] && [ -t 0 ]; then
    say "Unlocking the login keychain for signing (your Mac password)"
    security unlock-keychain ~/Library/Keychains/login.keychain-db
fi

say "Building (team $TEAM, bundle id $PREFIX.magmusic)"
xcodegen generate >/dev/null
mkdir -p build
xcodebuild -project MagMusic.xcodeproj -scheme MagMusic -configuration Release -derivedDataPath build \
    -allowProvisioningUpdates build > build/xcodebuild.log 2>&1 || { tail -20 build/xcodebuild.log; exit 1; }

say "Installing in /Applications"
pkill -x MagMusic 2>/dev/null && sleep 1 || true
rm -rf "$APP"
cp -R build/Build/Products/Release/MagMusic.app /Applications/

# The app group is MA_APP_GROUP in project.yml, $(TeamIdentifierPrefix)magmusic: the same for every prefix.
PREFS=~/Library/Group\ Containers/$TEAM.magmusic/Library/Preferences/$TEAM.magmusic.plist
if [ "$MODE" = "--token" ] || { [ "$MODE" = "install" ] && ! /usr/libexec/PlistBuddy -c "Print :server" "$PREFS" >/dev/null 2>&1; }; then
    say "Connect to Music Assistant"
    # MA_URL in the environment, else asked here (there is no default address).
    URL=$(ask_server) || { echo "No server address given. Run scripts/install.sh --token to set it."; exit 1; }
    TOKEN_FILE="$ROOT/.tools/ma_token"   # placed by a setup over SSH; used once, then deleted
    if [ -f "$TOKEN_FILE" ]; then
        TOKEN=$(cat "$TOKEN_FILE"); rm -f "$TOKEN_FILE"
        echo "Token: taken from the setup file (deleted)"
    else
        echo "Token: Music Assistant → Settings → Profile → Long-lived tokens (input is hidden)"
        read -r -s -p "Token: " TOKEN; echo
    fi
    MAGMUSIC_IMPORT=1 MA_URL="$URL" MA_TOKEN="$TOKEN" "$APP/Contents/MacOS/MagMusic" \
        || { unset TOKEN; echo "Saving the token failed."; exit 1; }
    unset TOKEN
fi

if [ "$MODE" != "--rebuild" ]; then
    say "Weekly rebuild (Sundays 12:00; log: $LOG)"
    mkdir -p ~/Library/LaunchAgents
    LABEL=$PREFIX.magmusic.rebuild
    AGENT=~/Library/LaunchAgents/$LABEL.plist
    cat > "$AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>/bin/bash</string><string>$ROOT/scripts/install.sh</string><string>--rebuild</string></array>
  <key>EnvironmentVariables</key><dict><key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string></dict>
  <key>StartCalendarInterval</key><dict><key>Weekday</key><integer>0</integer><key>Hour</key><integer>12</integer><key>Minute</key><integer>0</integer></dict>
  <key>StandardOutPath</key><string>$LOG</string>
  <key>StandardErrorPath</key><string>$LOG</string>
</dict></plist>
PLIST
    launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
    launchctl bootstrap gui/$(id -u) "$AGENT"
fi

open -a "$APP"
say "Done. MagMusic is in the menu bar; add the widget via right-click on the desktop → Edit Widgets."
