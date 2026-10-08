import AppIntents
import MAKit
import SwiftUI
import WidgetKit

struct Entry: TimelineEntry {
    var date: Date
    var player: PlayerSnap?
    var discover: [DiscoverSnap]
    var configured: Bool
    var speakers: [PlayerSnap] = []
}

struct Provider: AppIntentTimelineProvider {
    let store = SharedStore()

    func placeholder(in context: Context) -> Entry {
        Entry(date: .now, player: nil, discover: [], configured: true)
    }

    func snapshot(for configuration: SelectPlayerIntent, in context: Context) async -> Entry {
        entry(store.load(), configuration, at: .now)
    }

    func timeline(for configuration: SelectPlayerIntent, in context: Context) async -> Timeline<Entry> {
        let now = Date()
        let first = entry(store.load(), configuration, at: now)
        var entries = [first]
        // The app redraws on changes; within one track the system runs the progress bar, and at its end the
        // next track takes over without a redraw.
        if let player = first.player, let np = player.nowPlaying, let end = np.endDate(at: now), let next = player.next {
            var then = first
            then.date = end
            then.player?.nowPlaying = next.startingPlay(at: end)
            then.player?.next = nil
            entries.append(then)
            let after = next.duration.map { end.addingTimeInterval($0) } ?? end.addingTimeInterval(900)
            return Timeline(entries: entries, policy: .after(after))
        }
        return Timeline(entries: entries, policy: .after(now.addingTimeInterval(900)))
    }

    func entry(_ snap: Snapshot, _ config: SelectPlayerIntent, at date: Date) -> Entry {
        let chosen = config.player?.id.isEmpty == false ? config.player?.id : nil
        return Entry(date: date, player: snap.activePlayer(preferred: chosen ?? store.preferredPlayer),
                     discover: snap.discover, configured: store.server != nil,
                     speakers: snap.players.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
    }
}

struct NowPlayingWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "NowPlaying", intent: SelectPlayerIntent.self, provider: Provider()) { entry in
            WidgetView(entry: entry)
        }
        .configurationDisplayName("Music Assistant")
        .description("What a speaker plays, with controls and the Discover covers.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
    }
}

@main
struct MagMusicWidgets: WidgetBundle {
    var body: some Widget { NowPlayingWidget() }
}
