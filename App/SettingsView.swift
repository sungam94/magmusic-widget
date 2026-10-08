import MAKit
import SwiftUI

struct SettingsView: View {
    @Environment(Engine.self) private var engine
    @State private var server = SharedStore().server?.absoluteString ?? ""   // empty until the user enters one
    @State private var token = ""
    @State private var saved = false

    var body: some View {
        Form {
            TextField("Music Assistant", text: $server, prompt: Text("http://host:8095"))
            SecureField("Token", text: $token, prompt: Text(Credentials.token == nil ? "Long-lived token from MA" : "Saved — paste to replace"))
            Text("Create a token in Music Assistant under Settings → Profile → Long-lived tokens. It is kept in the keychain.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Open at login", isOn: Binding(get: { engine.launchAtLogin }, set: { engine.launchAtLogin = $0 }))
            Section("Speakers") {
                ForEach(engine.allPlayers.sorted { ($0.displayName ?? "") < ($1.displayName ?? "") }, id: \.playerId) { p in
                    Toggle(p.playerId == engine.store.localPlayer ? "This Mac (\(p.displayName ?? p.playerId))" : p.displayName ?? p.playerId,
                           isOn: Binding(get: { engine.store.speakers?.contains(p.playerId) ?? false },
                                         set: { engine.setSpeaker(p.playerId, on: $0) }))
                }
            }
            HStack {
                Text(engine.status).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Save") { save() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    func save() {
        guard let url = URL(string: server.trimmingCharacters(in: .whitespaces)), url.scheme?.hasPrefix("http") == true else { return }
        engine.store.server = url
        if !token.isEmpty { Credentials.save(token.trimmingCharacters(in: .whitespacesAndNewlines)) }
        token = ""
        engine.restart()
    }
}
