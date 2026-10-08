import Foundation

public enum SnapshotBuilder {
    /// Rows whose playlists wear the bridge's covers. The bridge's own rows come from its MA plugin
    /// ("spotify_bridge"); TIDAL and SoundCloud rows are named as in the bridge's config source_rows.
    public static let sourceRowPrefixes = ["Custom mixes", "Mixed for", "Made for you"]
    static let ourCoverPrefix = "sbcover_"

    public static func wantsRow(_ row: MARecommendationRow) -> Bool {
        row.provider.hasPrefix("spotify_bridge")
            || sourceRowPrefixes.contains { row.name.lowercased().hasPrefix($0.lowercased()) }
    }

    /// The MA player that is this Mac: the one at one of its addresses.
    public static func localPlayer(_ players: [MAPlayer], localAddresses: [String]) -> String? {
        players.first { p in p.deviceInfo?.ipAddress.map(localAddresses.contains) ?? false }?.playerId
    }

    /// The speakers listed until the user picks others in Settings: every player MA lists, and this Mac
    /// (even when MA hides it).
    public static func defaultSpeakers(_ players: [MAPlayer], localAddresses: [String]) -> [String] {
        let listed = players.filter(\.isListed).map(\.playerId)
        guard let local = localPlayer(players, localAddresses: localAddresses), !listed.contains(local) else { return listed }
        return listed + [local]
    }

    /// `speakers`: the chosen player ids (listed while available, even when hidden in MA); nil lists every
    /// player MA shows. `localId` is called "This Mac".
    public static func build(players: [MAPlayer], queues: [MAQueue], rows: [MARecommendationRow], now: Date,
                             speakers: [String]? = nil, localId: String? = nil) -> Snapshot {
        let byId = Dictionary(queues.map { ($0.queueId, $0) }, uniquingKeysWith: { a, _ in a })
        let chosen = players.filter { p in
            if let speakers, !speakers.isEmpty { return speakers.contains(p.playerId) && p.available == true }
            return p.isListed
        }
        let listed = chosen.map { p -> PlayerSnap in
            let queue = p.activeSource.flatMap { byId[$0] } ?? byId[p.playerId]
            let state = PlaybackState(rawValue: p.playbackState ?? "") ?? .idle
            return PlayerSnap(id: p.playerId, queueId: queue?.queueId ?? p.playerId,
                              name: p.playerId == localId ? "This Mac" : p.displayName ?? p.name ?? p.playerId,
                              state: state, volume: p.volumeLevel,
                              nowPlaying: queue.flatMap { nowPlaying($0, playing: state == .playing, now: now) },
                              next: queue?.nextItem.map { track($0, elapsed: 0, at: now, playing: false) },
                              lastActive: queue?.elapsedTimeLastUpdated.map { Date(timeIntervalSince1970: $0) })
        }
        let sorted = listed.sorted { a, b in
            if (a.state == .playing) != (b.state == .playing) { return a.state == .playing }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
        return Snapshot(players: sorted, discover: discover(rows), updatedAt: now)
    }

    static func nowPlaying(_ q: MAQueue, playing: Bool, now: Date) -> NowPlaying? {
        q.currentItem.map { track($0, elapsed: q.elapsedTime ?? 0,
                                  at: q.elapsedTimeLastUpdated.map { Date(timeIntervalSince1970: $0) } ?? now, playing: playing) }
    }

    static func track(_ item: MAQueueItem, elapsed: Double, at date: Date, playing: Bool) -> NowPlaying {
        let media = item.mediaItem
        let artist = media?.artists?.map(\.name).joined(separator: ", ") ?? ""
        let image = item.image ?? media?.thumb
        return NowPlaying(title: media?.name ?? item.name, artist: artist, album: media?.album?.name,
                          duration: item.duration, elapsed: elapsed, elapsedAt: date, isPlaying: playing,
                          coverKey: image?.proxyId, uri: media?.uri)
    }

    /// One playlist from each row in turn, so the first covers a widget shows mix the sources and moods.
    static func discover(_ rows: [MARecommendationRow]) -> [DiscoverSnap] {
        var seen = Set<String>()
        var perRow: [[DiscoverSnap]] = []
        for row in rows where wantsRow(row) {
            let ours = row.provider.hasPrefix("spotify_bridge")
            var list: [DiscoverSnap] = []
            for item in row.items ?? [] where item.mediaType == "playlist" {
                guard let uri = item.uri, let thumb = item.thumb, thumb.proxyId != nil,
                      ours || thumb.path.hasPrefix(ourCoverPrefix), seen.insert(uri).inserted else { continue }
                list.append(DiscoverSnap(uri: uri, name: item.name, row: row.name, coverKey: thumb.proxyId))
            }
            if !list.isEmpty { perRow.append(list) }
        }
        var out: [DiscoverSnap] = []
        for i in 0..<(perRow.map(\.count).max() ?? 0) {
            for list in perRow where i < list.count { out.append(list[i]) }
        }
        return out
    }
}
