import Foundation

public enum PlaybackState: String, Codable, Sendable { case playing, paused, idle }

public struct NowPlaying: Codable, Hashable, Sendable {
    public var title: String
    public var artist: String
    public var album: String?
    public var duration: Double?
    public var elapsed: Double
    public var elapsedAt: Date
    public var isPlaying: Bool
    public var coverKey: String?
    public var uri: String?

    /// Seconds into the track at `date`: runs on while playing, never past the end.
    public func elapsed(at date: Date) -> Double {
        let run = isPlaying ? max(0, date.timeIntervalSince(elapsedAt)) : 0
        let value = elapsed + run
        if let duration, duration > 0 { return min(value, duration) }
        return value
    }

    /// When the track started, so a widget can let the system run the progress bar without redraws.
    public func startDate(at date: Date) -> Date { date.addingTimeInterval(-elapsed(at: date)) }

    /// When it ends if it keeps playing; nil when paused or of unknown length.
    public func endDate(at date: Date) -> Date? {
        guard isPlaying, let duration, duration > 0 else { return nil }
        return startDate(at: date).addingTimeInterval(duration)
    }

    /// This track (a queue's next one) playing from its start at `date`.
    public func startingPlay(at date: Date) -> NowPlaying {
        var np = self
        np.elapsed = 0
        np.elapsedAt = date
        np.isPlaying = true
        return np
    }
}

public struct PlayerSnap: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var queueId: String
    public var name: String
    public var state: PlaybackState
    public var volume: Int?
    public var nowPlaying: NowPlaying?
    public var next: NowPlaying?
    public var lastActive: Date?
}

public struct DiscoverSnap: Codable, Hashable, Sendable, Identifiable {
    public var uri: String
    public var name: String
    public var row: String
    public var coverKey: String?
    public var id: String { uri }
}

/// Everything the widget draws, written by the menu bar app (or fetched by the widget itself) into the shared
/// container, so drawing a widget needs no network.
public struct Snapshot: Codable, Hashable, Sendable {
    public var players: [PlayerSnap]
    public var discover: [DiscoverSnap]
    public var updatedAt: Date

    public init(players: [PlayerSnap], discover: [DiscoverSnap], updatedAt: Date) {
        self.players = players
        self.discover = discover
        self.updatedAt = updatedAt
    }

    public static let empty = Snapshot(players: [], discover: [], updatedAt: .distantPast)

    /// The speaker after `id` by name, wrapping around; the first one for an unknown id.
    public func speaker(after id: String?) -> String? {
        let ordered = players.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        guard let i = ordered.firstIndex(where: { $0.id == id }) else { return ordered.first?.id }
        return ordered[(i + 1) % ordered.count].id
    }

    /// The chosen player if it is listed, else one that is playing, else the one with a track that was active
    /// most recently (a player with an empty queue only when none has a track).
    public func activePlayer(preferred: String?) -> PlayerSnap? {
        if let preferred, let p = players.first(where: { $0.id == preferred }) { return p }
        if let p = players.first(where: { $0.state == .playing }) { return p }
        let withTrack = players.filter { $0.nowPlaying != nil }
        return (withTrack.isEmpty ? players : withTrack).max { ($0.lastActive ?? .distantPast) < ($1.lastActive ?? .distantPast) }
    }
}

public extension JSONEncoder {
    static var ma: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }
}

public extension JSONDecoder {
    static var ma: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }
}
