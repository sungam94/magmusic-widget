# MagMusic

A macOS menu bar mini player and desktop widget for [Music Assistant](https://music-assistant.io): what a
speaker plays, controls, volume, moving playback between speakers, and the Discover covers drawn by the
Discovery Bridge (the companion project that mirrors Spotify's personal playlists into Music Assistant). The
player works with any Music Assistant server; the Discover covers need the Discovery Bridge.

## Install on a Mac

1. Install Xcode from the App Store and open it once.
2. Xcode → Settings → Accounts → + → your Apple ID. Then Manage Certificates… → + → Apple Development.
3. In this folder: `scripts/install.sh`
   It builds and signs the app with your free Apple ID team, installs it in /Applications, asks once for your
   Music Assistant server (for example `http://<server-ip>:8095`) and a long-lived token (MA → Settings →
   Profile), and adds a weekly rebuild.
4. Right-click the desktop → Edit Widgets → MagMusic.

A free Apple ID signs apps for 7 days only; the weekly LaunchAgent (`<your prefix>.magmusic.rebuild`, Sundays
12:00, log in ~/Library/Logs/MagMusic-rebuild.log) rebuilds before that. Keep this folder where it is: the job
builds from it. `scripts/install.sh --token` sets the server and token again.

## Your own values

Nothing in this folder points at anyone's server or speakers. What is yours:

- **Signing team:** automatic. `install.sh` reads it from your Apple Development certificate and writes it to
  the untracked `Local.xcconfig`.
- **Bundle id prefix:** automatic. The app is `<prefix>.magmusic`, the widget `<prefix>.magmusic.widget`, and
  the keychain group they share `<prefix>.magmusic.shared`. On the first run `install.sh` takes the prefix
  from an installed MagMusic.app, else asks for one (Enter takes `local.<your team id>`), and writes it to
  `Local.xcconfig`; you can also put a line like `BUNDLE_ID_PREFIX = org.example` there before the first
  install. Changing it later makes a new app: the token and the widget have to be set up again. A build
  without `Local.xcconfig` uses `local.magmusic` from the tracked `Config.xcconfig`.
- **Server and token:** asked on the first run, or in Settings (the gear in the menu). The token is kept in
  the keychain. `MA_URL=http://<server-ip>:8095 scripts/install.sh` answers the server question ahead.
- **Speakers:** at first every player Music Assistant lists, plus this Mac. Pick yours in Settings →
  Speakers.
- **Discover rows:** the widget shows the Discovery Bridge's own rows, and the TIDAL and SoundCloud rows whose
  names start with "Custom mixes", "Mixed for" or "Made for you" (`SnapshotBuilder.sourceRowPrefixes`), and
  from those only playlists with the bridge's covers. These names must match the bridge's `source_rows`
  setting; if you change one there, change the other here.

## Layout

- `MAKit/`: Swift package with the MA WebSocket client, the snapshot the widget draws and the shared store.
- `App/`: the menu bar app, which keeps the connection and writes the snapshot.
- `Widget/`: the widget. `Shared/`: the App Intents both use.
- `project.yml`: XcodeGen project (the Xcode project is generated from it and not kept in git).
  `Config.xcconfig` holds the default bundle id prefix and includes your untracked `Local.xcconfig`.
- `scripts/install.sh`: build, sign, install, weekly rebuild. `scripts/install_lib.sh`: its helpers.

## Tests

- `cd MAKit && swift test`: the client, the snapshot and the Discover filter, against saved Music Assistant
  answers in `MAKit/Tests/MAKitTests/Fixtures`. The saved answers are anonymised by
  `scripts/anonymize_fixtures.py`; run it on any new ones you save.
- Live tests against your own server run only with both `MA_URL` and `MA_TOKEN` set; add
  `MA_EXPECT_DISCOVER=1` when the server runs the Discovery Bridge. They read and never change playback.
- `scripts/tests/test_install_xcconfig.sh`: the install helpers, in a temp folder.
- `scripts/tests/test_export_share.sh`: the owner patterns check of `scripts/export-share.sh`, in a throwaway
  repository.
- `scripts/tests/test_bundle_prefix.sh`: the bundle ids and keychain group for a prefix, on a temp copy
  (needs XcodeGen).

## Licence

MIT (see `LICENSE`).
