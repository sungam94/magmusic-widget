import AppIntents
import MAKit
import WidgetKit

/// Runs a command against MA, then writes a fresh snapshot and redraws the widgets. Compiled into the app and
/// the widget; as AudioPlaybackIntents the controls run in the app's process, which has the local network.
enum Remote {
    static func run(_ command: @Sendable (MAClient) async throws -> Void) async throws {
        let store = SharedStore()
        guard let client = Credentials.client(store) else { throw MAError.notConfigured }
        try await client.connect()
        do {
            try await command(client)
            try? await Task.sleep(for: .milliseconds(500))   // MA updates the queue right after the command
            let snap = try await client.snapshot(keepingDiscover: store.load().discover, speakers: store.speakers,
                                                 localId: store.localPlayer)
            await store.cacheCovers(store.coverKeys(snap), server: client.server)
            try store.save(snap)
        } catch {
            await client.close()
            throw error
        }
        await client.close()
        WidgetCenter.shared.reloadAllTimelines()
    }
}

struct PlayPauseIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play or Pause"
    static let isDiscoverable = false
    @Parameter(title: "Player") var playerId: String
    init() {}
    init(playerId: String) { self.playerId = playerId }
    func perform() async throws -> some IntentResult {
        let id = playerId
        try await Remote.run { try await $0.playPause(id) }
        return .result()
    }
}

struct NextTrackIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Next Track"
    static let isDiscoverable = false
    @Parameter(title: "Player") var playerId: String
    init() {}
    init(playerId: String) { self.playerId = playerId }
    func perform() async throws -> some IntentResult {
        let id = playerId
        try await Remote.run { try await $0.next(id) }
        return .result()
    }
}

struct PreviousTrackIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Previous Track"
    static let isDiscoverable = false
    @Parameter(title: "Player") var playerId: String
    init() {}
    init(playerId: String) { self.playerId = playerId }
    func perform() async throws -> some IntentResult {
        let id = playerId
        try await Remote.run { try await $0.previous(id) }
        return .result()
    }
}

struct VolumeStepIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Change Volume"
    static let isDiscoverable = false
    @Parameter(title: "Player") var playerId: String
    @Parameter(title: "Up") var up: Bool
    init() {}
    init(playerId: String, up: Bool) {
        self.playerId = playerId
        self.up = up
    }
    func perform() async throws -> some IntentResult {
        let id = playerId, louder = up
        try await Remote.run { louder ? try await $0.volumeUp(id) : try await $0.volumeDown(id) }
        return .result()
    }
}

struct PlayPlaylistIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play Playlist"
    static let isDiscoverable = false
    @Parameter(title: "Playlist") var uri: String
    @Parameter(title: "Player queue") var queueId: String
    init() {}
    init(uri: String, queueId: String) {
        self.uri = uri
        self.queueId = queueId
    }
    func perform() async throws -> some IntentResult {
        let uri = uri, queue = queueId
        try await Remote.run { try await $0.play(uri, on: queue) }
        return .result()
    }
}

/// Moves what plays to another speaker; the widgets and the menu then follow that speaker.
struct MoveToSpeakerIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Move to Speaker"
    static let isDiscoverable = false
    @Parameter(title: "From queue") var fromQueue: String
    @Parameter(title: "To speaker") var toPlayer: String
    @Parameter(title: "To queue") var toQueue: String
    init() {}
    init(fromQueue: String, toPlayer: String, toQueue: String) {
        self.fromQueue = fromQueue
        self.toPlayer = toPlayer
        self.toQueue = toQueue
    }
    func perform() async throws -> some IntentResult {
        let from = fromQueue, to = toQueue
        SharedStore().preferredPlayer = toPlayer
        try await Remote.run { try await $0.transfer(from: from, to: to) }
        return .result()
    }
}

/// Switches the widgets (those following "whichever is playing") and the menu to the next speaker.
struct NextSpeakerIntent: AppIntent {
    static let title: LocalizedStringResource = "Next Speaker"
    static let isDiscoverable = false
    @Parameter(title: "Current speaker") var playerId: String
    init() {}
    init(playerId: String) { self.playerId = playerId }
    func perform() async throws -> some IntentResult {
        let store = SharedStore()
        store.preferredPlayer = store.load().speaker(after: playerId)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

// MARK: - Which player a widget follows

struct PlayerEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Player"
    static let defaultQuery = PlayerQuery()
    static let follow = PlayerEntity(id: "", name: "Whichever is playing")

    var id: String
    var name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct PlayerQuery: EntityQuery {
    func all() -> [PlayerEntity] {
        [.follow] + SharedStore().load().players.map { PlayerEntity(id: $0.id, name: $0.name) }
    }
    func entities(for identifiers: [String]) async throws -> [PlayerEntity] {
        let known = all()
        return identifiers.map { id in known.first { $0.id == id } ?? PlayerEntity(id: id, name: "Player") }
    }
    func suggestedEntities() async throws -> [PlayerEntity] { all() }
    func defaultResult() async -> PlayerEntity? { .follow }
}

struct SelectPlayerIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Player"
    static let description = IntentDescription("The speaker this widget shows and controls.")
    @Parameter(title: "Player") var player: PlayerEntity?
    init() {}
}
