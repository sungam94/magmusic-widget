import Darwin
import Foundation
import MAKit
import Observation
import ServiceManagement
import WidgetKit

/// Keeps one connection to Music Assistant, follows its events and writes the snapshot the widget draws.
/// The widget is redrawn only when something it shows changes, because macOS limits widget redraws.
@MainActor @Observable
final class Engine {
    static let shared = Engine()

    let store = SharedStore()
    private(set) var snapshot: Snapshot
    private(set) var status = "Not connected"
    private(set) var connected = false
    /// Every available MA player, for choosing the speakers in Settings.
    private(set) var allPlayers: [MAPlayer] = []
    var selectedPlayerId: String? {
        didSet { store.preferredPlayer = selectedPlayerId; WidgetCenter.shared.reloadAllTimelines() }
    }

    private var client: MAClient?
    private var loop: Task<Void, Never>?
    private var pendingRefresh: Task<Void, Never>?
    private var lastDiscover = Date.distantPast
    private var lastSignature = ""
    static let discoverEvery: TimeInterval = 15 * 60
    static let refreshingEvents: Set<String> = ["player_updated", "player_added", "player_removed", "queue_updated",
                                                "queue_items_updated"]

    private init() {
        snapshot = store.load()
        selectedPlayerId = store.preferredPlayer
    }

    var player: PlayerSnap? { snapshot.activePlayer(preferred: selectedPlayerId) }

    func start() {
        loop?.cancel()
        loop = Task { await run() }
    }

    func restart() {
        Task { await client?.close() }
        lastDiscover = .distantPast
        start()
    }

    private func run() async {
        var backoff: Double = 2
        while !Task.isCancelled {
            guard let c = Credentials.client(store) else {
                status = "Add the server and token in Settings"
                connected = false
                try? await Task.sleep(for: .seconds(5))
                continue
            }
            client = c
            let events = await c.events()
            do {
                status = "Connecting…"
                try await c.connect()
                connected = true
                status = "Connected"
                backoff = 2
                await chooseSpeakers(c)
                await refresh(discover: true)
                for await event in events {
                    if let name = event.event, Self.refreshingEvents.contains(name) { scheduleRefresh() }
                    if Date().timeIntervalSince(lastDiscover) > Self.discoverEvery { scheduleRefresh() }
                }
                status = "Connection lost; reconnecting"
            } catch {
                status = "Cannot reach Music Assistant (\(Self.describe(error)))"
            }
            connected = false
            await c.close()
            try? await Task.sleep(for: .seconds(backoff))
            backoff = min(backoff * 2, 60)
        }
    }

    /// Finds this Mac among MA's players and, the first time, lists the default speakers.
    private func chooseSpeakers(_ c: MAClient) async {
        guard let players = try? await c.players() else { return }
        allPlayers = players.filter { $0.available == true }
        let addresses = Self.localAddresses()
        if let local = SnapshotBuilder.localPlayer(players, localAddresses: addresses) { store.localPlayer = local }
        if store.speakers == nil { store.speakers = SnapshotBuilder.defaultSpeakers(players, localAddresses: addresses) }
    }

    func setSpeaker(_ id: String, on: Bool) {
        var list = store.speakers ?? []
        if on { if !list.contains(id) { list.append(id) } } else { list.removeAll { $0 == id } }
        store.speakers = list
        Task { await refresh(discover: false) }
    }

    /// This Mac's IPv4 addresses.
    static func localAddresses() -> [String] {
        var out: [String] = []
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0 else { return out }
        defer { freeifaddrs(head) }
        var cur = head
        while let p = cur {
            if let sa = p.pointee.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    out.append(String(cString: host))
                }
            }
            cur = p.pointee.ifa_next
        }
        return out
    }

    static func describe(_ error: Error) -> String {
        switch error {
        case MAError.server(_, let details): details
        case MAError.timeout(let what): "no answer to \(what)"
        default: error.localizedDescription
        }
    }

    private func scheduleRefresh() {
        pendingRefresh?.cancel()
        pendingRefresh = Task {
            try? await Task.sleep(for: .milliseconds(400))   // events come in bursts
            guard !Task.isCancelled else { return }
            await refresh(discover: Date().timeIntervalSince(lastDiscover) > Self.discoverEvery)
        }
    }

    func refresh(discover: Bool) async {
        guard let c = client else { return }
        do {
            let speakers = store.speakers, local = store.localPlayer
            let snap = discover ? try await c.snapshot(speakers: speakers, localId: local)
                : try await c.snapshot(keepingDiscover: snapshot.discover, speakers: speakers, localId: local)
            if discover { lastDiscover = Date() }
            await store.cacheCovers(store.coverKeys(snap), server: c.server)
            if discover { store.pruneCovers(keeping: Set(store.coverKeys(snap))) }
            snapshot = snap
            if store.preferredPlayer != selectedPlayerId { selectedPlayerId = store.preferredPlayer }  // switched in a widget
            try store.save(snap)
            let sig = Self.signature(snap)
            if sig != lastSignature {
                lastSignature = sig
                WidgetCenter.shared.reloadAllTimelines()
            }
        } catch {
            status = "Refresh failed (\(Self.describe(error)))"
        }
    }

    /// What the widget shows, without the running clock: a seek moves the start by more than two seconds.
    static func signature(_ s: Snapshot) -> String {
        let now = Date()
        return s.players.map { p in
            let np = p.nowPlaying
            let start = np.map { Int($0.startDate(at: now).timeIntervalSince1970 / 2) } ?? 0
            return "\(p.id)|\(p.state)|\(p.volume ?? -1)|\(np?.title ?? "")|\(np?.uri ?? "")|\(np?.isPlaying ?? false)|\(start)|\(p.next?.uri ?? "")"
        }.joined(separator: ";") + "#" + s.discover.map(\.uri).joined(separator: ",")
    }

    // MARK: commands from the menu

    func perform(_ command: @escaping @Sendable (MAClient) async throws -> Void) {
        guard let c = client else { return }
        Task {
            do {
                try await command(c)
            } catch {
                status = "Command failed (\(Self.describe(error)))"
            }
        }
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                status = "Launch at login: \(error.localizedDescription)"
            }
        }
    }
}
