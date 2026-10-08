import MAKit
import SwiftUI

/// The mini player in the menu bar: the chosen speaker, what it plays, controls, volume and the Discover covers.
struct MenuView: View {
    @Environment(Engine.self) private var engine
    @Environment(\.openWindow) private var openWindow
    @State private var volume: Double = 0
    @State private var editingVolume = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            playerPicker
            if let p = engine.player {
                nowPlaying(p)
                controls(p)
                volumeRow(p)
            } else {
                Text(engine.status).font(.callout).foregroundStyle(.secondary)
            }
            if !engine.snapshot.discover.isEmpty { discover }
            footer
        }
        .padding(14)
        .frame(width: 340)
        .onAppear { volume = Double(engine.player?.volume ?? 0) }
        .onChange(of: engine.player?.volume) { _, v in if !editingVolume { volume = Double(v ?? 0) } }
    }

    var playerPicker: some View {
        @Bindable var engine = engine
        return HStack {
            Picker(selection: $engine.selectedPlayerId) {
                Text("Whichever is playing").tag(String?.none)
                ForEach(engine.snapshot.players) { p in
                    Text(p.state == .playing ? "\(p.name) ♪" : p.name).tag(Optional(p.id))
                }
            } label: { Image(systemName: "hifispeaker.fill") }
            .pickerStyle(.menu)
            if let current = engine.player, current.nowPlaying != nil {
                Menu("Move to…") {
                    ForEach(engine.snapshot.players.filter { $0.id != current.id }) { other in
                        Button(other.name) {
                            engine.selectedPlayerId = other.id
                            engine.perform { try await $0.transfer(from: current.queueId, to: other.queueId) }
                        }
                    }
                }
                .menuStyle(.borderlessButton).fixedSize()
                .help("Move what plays to another speaker")
            }
        }
    }

    func cover(_ key: String?) -> some View {
        Group {
            if let key, let ns = NSImage(contentsOf: engine.store.coverFile(key)) {
                Image(nsImage: ns).resizable().scaledToFill()
            } else {
                Rectangle().fill(.quaternary).overlay(Image(systemName: "music.note").foregroundStyle(.secondary))
            }
        }
    }

    func nowPlaying(_ p: PlayerSnap) -> some View {
        HStack(alignment: .top, spacing: 12) {
            cover(p.nowPlaying?.coverKey).frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(p.nowPlaying?.title ?? "Nothing playing").font(.headline).lineLimit(2)
                Text(p.nowPlaying?.artist ?? "").font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                if let album = p.nowPlaying?.album { Text(album).font(.caption).foregroundStyle(.tertiary).lineLimit(1) }
                Spacer(minLength: 0)
                if let np = p.nowPlaying { ProgressRow(np: np, queueId: p.queueId) }
            }
        }
    }

    func controls(_ p: PlayerSnap) -> some View {
        HStack(spacing: 22) {
            Spacer()
            Button { engine.perform { try await $0.previous(p.id) } } label: { Image(systemName: "backward.fill") }
            Button { engine.perform { try await $0.playPause(p.id) } } label: {
                Image(systemName: p.state == .playing ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 34))
            }
            Button { engine.perform { try await $0.next(p.id) } } label: { Image(systemName: "forward.fill") }
            Spacer()
        }
        .buttonStyle(.plain).font(.title3)
    }

    func volumeRow(_ p: PlayerSnap) -> some View {
        HStack {
            Image(systemName: "speaker.fill").foregroundStyle(.secondary)
            Slider(value: $volume, in: 0...100) { editing in
                editingVolume = editing
                if !editing {
                    let level = Int(volume)
                    engine.perform { try await $0.setVolume(p.id, level) }
                }
            }
            Text("\(Int(volume))").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 26)
        }
        .disabled(p.volume == nil)
    }

    var discover: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("DISCOVER").font(.caption2.weight(.bold)).tracking(1.5).foregroundStyle(.secondary)
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                    ForEach(engine.snapshot.discover) { item in
                        Button {
                            guard let p = engine.player else { return }
                            engine.perform { try await $0.play(item.uri, on: p.queueId) }
                        } label: {
                            cover(item.coverKey).aspectRatio(1, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        }
                        .buttonStyle(.plain).help("\(item.name) · \(item.row)")
                    }
                }
            }
            .frame(maxHeight: 250)
        }
    }

    var footer: some View {
        HStack {
            Circle().fill(engine.connected ? .green : .orange).frame(width: 7, height: 7)
            Text(engine.status).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            Button {
                NSApp.activate(ignoringOtherApps: true)   // a menu bar app is never active on its own
                openWindow(id: "settings")
            } label: { Image(systemName: "gearshape") }
            .buttonStyle(.plain).help("Settings")
            Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }.buttonStyle(.plain)
        }
    }
}

/// Elapsed and remaining time, ticking every second; drag to seek.
struct ProgressRow: View {
    @Environment(Engine.self) private var engine
    let np: NowPlaying
    let queueId: String
    @State private var dragging: Double?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let duration = np.duration ?? 0
            let at = dragging ?? np.elapsed(at: ctx.date)
            VStack(spacing: 2) {
                if duration > 0 {
                    Slider(value: Binding(get: { at }, set: { dragging = $0 }), in: 0...duration) { editing in
                        if !editing, let to = dragging {
                            engine.perform { try await $0.seek(queueId, to: Int(to)) }
                            dragging = nil
                        }
                    }
                    .controlSize(.mini)
                }
                HStack {
                    Text(Self.clock(at)); Spacer(); Text(duration > 0 ? "-" + Self.clock(duration - at) : "")
                }
                .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
    }

    static func clock(_ s: Double) -> String {
        let t = Int(max(0, s))
        return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, t % 3600 / 60, t % 60) : String(format: "%d:%02d", t / 60, t % 60)
    }
}
