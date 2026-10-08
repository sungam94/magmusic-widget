import Foundation

/// Music Assistant's WebSocket API: commands with replies, and the events MA pushes after auth.
public actor MAClient {
    public let server: URL
    private let token: String
    private let timeout: TimeInterval
    private var task: URLSessionWebSocketTask?
    private var pending: [String: CheckedContinuation<Data?, Error>] = [:]
    private var nextId = 1
    private var eventContinuation: AsyncStream<MAMessage>.Continuation?

    public init(server: URL, token: String, timeout: TimeInterval = 15) {
        self.server = server
        self.token = token
        self.timeout = timeout
    }

    public static func socketURL(_ server: URL) -> URL {
        var parts = URLComponents(url: server, resolvingAgainstBaseURL: false)!
        parts.scheme = parts.scheme == "https" ? "wss" : "ws"
        parts.path = "/ws"
        return parts.url!
    }

    /// Events after connect(); the stream ends when the connection does.
    public func events() -> AsyncStream<MAMessage> {
        let (stream, continuation) = AsyncStream<MAMessage>.makeStream(bufferingPolicy: .bufferingNewest(200))
        eventContinuation = continuation
        return stream
    }

    public var isConnected: Bool { task != nil }

    public func connect() async throws {
        dropSocket()   // an old socket only: the event stream opened for this connection must stay open
        let ws = URLSession.shared.webSocketTask(with: Self.socketURL(server))
        ws.maximumMessageSize = 64 * 1024 * 1024
        ws.resume()
        task = ws
        _ = try await withTimeout("server info") { try await ws.receive() }   // MA greets with its server info
        Task { await self.receiveLoop(ws) }
        _ = try await raw("auth", ["token": .string(token)])
    }

    public func close() {
        dropSocket()
        eventContinuation?.finish()
        eventContinuation = nil
    }

    private func dropSocket() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        for (_, c) in pending { c.resume(throwing: MAError.notConnected) }
        pending = [:]
    }

    public func call<T: Decodable & Sendable>(_ command: String, _ args: [String: JSONValue] = [:],
                                               as type: T.Type) async throws -> T {
        guard let data = try await raw(command, args) else { throw MAError.badMessage }
        return try JSONDecoder().decode(T.self, from: data)
    }

    public func send(_ command: String, _ args: [String: JSONValue] = [:]) async throws {
        _ = try await raw(command, args)
    }

    private func raw(_ command: String, _ args: [String: JSONValue]) async throws -> Data? {
        guard let ws = task else { throw MAError.notConnected }
        let id = String(nextId)
        nextId += 1
        let payload = try MAMessage.command(id: id, command, args)
        let deadline = timeout
        return try await withThrowingTaskGroup(of: Data?.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { c in
                    Task { await self.register(id, c, ws, payload) }
                }
            }
            group.addTask {
                try await Task.sleep(for: .seconds(deadline))
                await self.fail(id, MAError.timeout(command))
                throw MAError.timeout(command)
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }

    private func register(_ id: String, _ c: CheckedContinuation<Data?, Error>, _ ws: URLSessionWebSocketTask,
                          _ payload: Data) async {
        pending[id] = c
        do {
            try await ws.send(.string(String(decoding: payload, as: UTF8.self)))
        } catch {
            fail(id, error)
        }
    }

    private func fail(_ id: String, _ error: Error) {
        pending.removeValue(forKey: id)?.resume(throwing: error)
    }

    private func receiveLoop(_ ws: URLSessionWebSocketTask) async {
        while task === ws {
            do {
                let data: Data
                switch try await ws.receive() {
                case .data(let d): data = d
                case .string(let s): data = Data(s.utf8)
                @unknown default: continue
                }
                let msg = try MAMessage.parse(data)
                if let id = msg.messageId, let c = pending.removeValue(forKey: id) {
                    if let error = msg.error { c.resume(throwing: error) } else { c.resume(returning: msg.result) }
                } else if msg.event != nil {
                    eventContinuation?.yield(msg)
                }
            } catch {
                if task === ws { close() }
                return
            }
        }
    }

    private func withTimeout<T: Sendable>(_ what: String, _ body: @escaping @Sendable () async throws -> T) async throws -> T {
        let deadline = timeout
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await body() }
            group.addTask {
                try await Task.sleep(for: .seconds(deadline))
                throw MAError.timeout(what)
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }
}

// MARK: - The commands the widget and the menu use

public extension MAClient {
    func players() async throws -> [MAPlayer] { try await call("players/all", as: [MAPlayer].self) }
    func queues() async throws -> [MAQueue] { try await call("player_queues/all", as: [MAQueue].self) }

    func playPause(_ playerId: String) async throws { try await send("players/cmd/play_pause", ["player_id": .string(playerId)]) }
    func next(_ playerId: String) async throws { try await send("players/cmd/next", ["player_id": .string(playerId)]) }
    func previous(_ playerId: String) async throws { try await send("players/cmd/previous", ["player_id": .string(playerId)]) }
    func volumeUp(_ playerId: String) async throws { try await send("players/cmd/volume_up", ["player_id": .string(playerId)]) }
    func volumeDown(_ playerId: String) async throws { try await send("players/cmd/volume_down", ["player_id": .string(playerId)]) }
    func setVolume(_ playerId: String, _ level: Int) async throws {
        try await send("players/cmd/volume_set", ["player_id": .string(playerId), "volume_level": .int(max(0, min(100, level)))])
    }
    func seek(_ queueId: String, to seconds: Int) async throws {
        try await send("player_queues/seek", ["queue_id": .string(queueId), "position": .int(max(0, seconds))])
    }
    /// Moves the queue (and its playback, if playing) to another speaker.
    func transfer(from source: String, to target: String) async throws {
        try await send("player_queues/transfer", ["source_queue_id": .string(source), "target_queue_id": .string(target)])
    }

    /// Replaces what the player plays with the playlist (or any media uri).
    func play(_ uri: String, on queueId: String) async throws {
        try await send("player_queues/play_media", ["queue_id": .string(queueId), "media": .string(uri), "option": "replace"])
    }

    /// Discover rows the widget shows covers from: the bridge's own rows, and the TIDAL/SoundCloud rows whose
    /// playlists carry the bridge's covers. Other rows are not fetched (each row is a request to its provider).
    func discoverRows() async throws -> [MARecommendationRow] {
        let rows = try await call("music/recommendations", as: [MARecommendationRow].self)
        var out: [MARecommendationRow] = []
        for var row in rows where SnapshotBuilder.wantsRow(row) {
            row.items = (try? await call("music/recommendations/items",
                                         ["provider": .string(row.provider), "item_id": .string(row.itemId)],
                                         as: [MAMediaItem].self)) ?? []
            out.append(row)
        }
        return out
    }

    /// Players and queues fresh, Discover kept from an earlier snapshot (its rows are slow to fetch).
    func snapshot(keepingDiscover discover: [DiscoverSnap], speakers: [String]? = nil, localId: String? = nil) async throws -> Snapshot {
        var snap = SnapshotBuilder.build(players: try await players(), queues: try await queues(), rows: [], now: Date(),
                                         speakers: speakers, localId: localId)
        snap.discover = discover
        return snap
    }

    func snapshot(withDiscover rows: [MARecommendationRow]? = nil, speakers: [String]? = nil, localId: String? = nil) async throws -> Snapshot {
        let found: [MARecommendationRow]
        if let rows { found = rows } else { found = try await discoverRows() }
        return SnapshotBuilder.build(players: try await players(), queues: try await queues(), rows: found, now: Date(),
                                     speakers: speakers, localId: localId)
    }
}
