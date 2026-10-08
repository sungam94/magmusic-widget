import MAKit
import SwiftUI

@main
struct MagMusicApp: App {
    @State private var engine = Engine.shared

    init() {
        // Setup without typing: MAGMUSIC_IMPORT=1 with MA_URL and MA_TOKEN in the environment saves them
        // (token into the keychain) and quits. Nothing is printed.
        let env = ProcessInfo.processInfo.environment
        if env["MAGMUSIC_IMPORT"] == "1" {
            if let token = env["MA_TOKEN"], !token.isEmpty { Credentials.save(token) }
            if let url = env["MA_URL"].flatMap(URL.init(string:)) { Engine.shared.store.server = url }
            exit(Credentials.token == nil ? 1 : 0)
        }
        // A menu bar helper that ends with a logout is gone until opened by hand: on its first start it opens at
        // login (Settings can switch that off again).
        if !UserDefaults.standard.bool(forKey: "loginItemSet") {
            Engine.shared.launchAtLogin = true
            UserDefaults.standard.set(true, forKey: "loginItemSet")
        }
        Engine.shared.start()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuView().environment(engine)
        } label: {
            Image(systemName: engine.player?.state == .playing ? "music.note" : "music.note.list")
        }
        .menuBarExtraStyle(.window)

        // A window of its own: SettingsLink does not open anything from a menu bar-only app.
        Window("MagMusic Settings", id: "settings") {
            SettingsView().environment(engine)
        }
        .windowResizability(.contentSize)
    }
}
