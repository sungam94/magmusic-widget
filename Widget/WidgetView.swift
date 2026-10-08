import AppIntents
import MAKit
import SwiftUI
import WidgetKit

struct WidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: Entry
    let store = SharedStore()

    var body: some View {
        content
            .containerBackground(for: .widget) { background }
    }

    @ViewBuilder var content: some View {
        if !entry.configured {
            Label("Open MagMusic to connect to Music Assistant", systemImage: "music.note")
                .font(.caption).foregroundStyle(.secondary)
        } else if let player = entry.player {
            switch family {
            case .systemSmall: small(player)
            case .systemMedium: medium(player)
            default: large(player)
            }
        } else {
            Label("No speaker found", systemImage: "hifispeaker").font(.caption).foregroundStyle(.secondary)
        }
    }

    var background: some View {
        ZStack {
            Color.black
            if let key = entry.player?.nowPlaying?.coverKey, cover(key) != nil {
                picture(key).blur(radius: 30).opacity(0.45)
            }
        }
    }

    func cover(_ key: String?) -> Image? {
        guard let key, let ns = NSImage(contentsOf: store.coverFile(key)) else { return nil }
        return Image(nsImage: ns)
    }

    /// A cover as a picture: in the desktop's tinted widget style macOS would draw it as a flat shape.
    func picture(_ key: String?) -> some View {
        Group {
            if let img = cover(key) {
                if #available(macOS 15.0, *) {
                    img.resizable().widgetAccentedRenderingMode(.fullColor).scaledToFill()
                } else {
                    img.resizable().scaledToFill()
                }
            } else {
                Rectangle().fill(.white.opacity(0.08)).overlay(Image(systemName: "music.note").foregroundStyle(.secondary))
            }
        }
    }

    func art(_ key: String?, _ side: CGFloat) -> some View {
        picture(key)
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: sizes

    func small(_ p: PlayerSnap) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                art(p.nowPlaying?.coverKey, 64)
                Spacer()
                playButton(p, size: 30)
            }
            Spacer(minLength: 0)
            titles(p, compact: true)
            progress(p)
            playerName(p)
        }
    }

    func medium(_ p: PlayerSnap, art side: CGFloat = 130) -> some View {
        HStack(spacing: 14) {
            art(p.nowPlaying?.coverKey, side)
            VStack(alignment: .leading, spacing: 6) {
                playerName(p)
                titles(p, compact: false)
                Spacer(minLength: 0)
                progress(p)
                controls(p)
            }
        }
    }

    /// Large: the player on top, two rows of four covers. Extra large: the player at the left, a 4 x 3 grid of
    /// covers at the right. Cell sizes are fixed so the content always fits the widget's height.
    @ViewBuilder func large(_ p: PlayerSnap) -> some View {
        if family == .systemExtraLarge {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    art(p.nowPlaying?.coverKey, 170)
                    playerName(p)
                    titles(p, compact: false)
                    Spacer(minLength: 0)
                    progress(p)
                    controls(p)
                }
                .frame(width: 210)
                VStack(alignment: .leading, spacing: 10) {
                    moveRow(p)
                    discoverGrid(p, columns: 4, rows: 3, cell: 88)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                medium(p, art: 100).frame(height: 100)
                moveRow(p)
                discoverGrid(p, columns: 4, rows: 2, cell: 66)
            }
        }
    }

    /// The other speakers; a tap moves what plays there.
    func moveRow(_ p: PlayerSnap) -> some View {
        HStack(spacing: 6) {
            Text("MOVE TO").font(.caption2.weight(.bold)).tracking(1.5).foregroundStyle(.secondary)
            ForEach(entry.speakers.filter { $0.id != p.id }) { other in
                Button(intent: MoveToSpeakerIntent(fromQueue: p.queueId, toPlayer: other.id, toQueue: other.queueId)) {
                    Text(other.name).font(.caption2.weight(.semibold)).lineLimit(1)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(.white.opacity(0.14)))
                }
                .buttonStyle(.plain).foregroundStyle(.white)
            }
        }
    }

    func discoverGrid(_ p: PlayerSnap, columns: Int, rows: Int, cell: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("DISCOVER").font(.caption2.weight(.bold)).tracking(1.5).foregroundStyle(.secondary)
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                ForEach(0..<rows, id: \.self) { r in
                    GridRow {
                        ForEach(Array(entry.discover.dropFirst(r * columns).prefix(columns))) { item in
                            Button(intent: PlayPlaylistIntent(uri: item.uri, queueId: p.queueId)) {
                                picture(item.coverKey).frame(width: cell, height: cell)
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // MARK: parts

    /// The speaker it plays on; tap for the next one.
    func playerName(_ p: PlayerSnap) -> some View {
        Button(intent: NextSpeakerIntent(playerId: p.id)) {
            HStack(spacing: 4) {
                Image(systemName: p.state == .playing ? "hifispeaker.fill" : "hifispeaker")
                Text(p.name).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").imageScale(.small)
            }
            .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    func titles(_ p: PlayerSnap, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(p.nowPlaying?.title ?? "Nothing playing")
                .font(compact ? .caption.weight(.bold) : .headline).lineLimit(family == .systemLarge ? 1 : 2)
            if let artist = p.nowPlaying?.artist, !artist.isEmpty {
                Text(artist).font(compact ? .caption2 : .subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .foregroundStyle(.white)
    }

    @ViewBuilder func progress(_ p: PlayerSnap) -> some View {
        if let np = p.nowPlaying, let duration = np.duration, duration > 0 {
            // The times say where the track is in every widget style; the tinted desktop style paints the bar white.
            VStack(spacing: 2) {
                if np.isPlaying {
                    let start = np.startDate(at: entry.date)
                    let end = start.addingTimeInterval(duration)
                    ProgressView(timerInterval: start...end, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                        .tint(.white)
                    if family != .systemSmall {
                        HStack {
                            Text(timerInterval: start...end, countsDown: false)
                            Spacer()
                            Text(timerInterval: start...end, countsDown: true)
                        }
                        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    }
                } else {
                    ProgressView(value: min(np.elapsed, duration), total: duration).tint(.white.opacity(0.6))
                    if family != .systemSmall {
                        HStack {
                            Text(Self.clock(np.elapsed))
                            Spacer()
                            Text("-" + Self.clock(duration - np.elapsed))
                        }
                        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    static func clock(_ s: Double) -> String {
        let t = Int(max(0, s))
        return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, t % 3600 / 60, t % 60) : String(format: "%d:%02d", t / 60, t % 60)
    }

    func playButton(_ p: PlayerSnap, size: CGFloat) -> some View {
        Button(intent: PlayPauseIntent(playerId: p.id)) {
            Image(systemName: p.state == .playing ? "pause.circle.fill" : "play.circle.fill")
                .resizable().frame(width: size, height: size)
        }
        .buttonStyle(.plain).foregroundStyle(.white)
    }

    func controls(_ p: PlayerSnap) -> some View {
        HStack(spacing: 14) {
            Button(intent: PreviousTrackIntent(playerId: p.id)) { Image(systemName: "backward.fill") }
            playButton(p, size: 26)
            Button(intent: NextTrackIntent(playerId: p.id)) { Image(systemName: "forward.fill") }
            Spacer()
            Button(intent: VolumeStepIntent(playerId: p.id, up: false)) { Image(systemName: "speaker.minus.fill") }
            if let v = p.volume { Text("\(v)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary) }
            Button(intent: VolumeStepIntent(playerId: p.id, up: true)) { Image(systemName: "speaker.plus.fill") }
        }
        .buttonStyle(.plain).foregroundStyle(.white).font(.callout)
    }
}
