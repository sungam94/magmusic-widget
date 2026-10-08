import Foundation
import Testing
@testable import MAKit

/// Against a real Music Assistant; runs only with both MA_URL and MA_TOKEN set. Reads, never changes playback.
/// MA_EXPECT_DISCOVER=1 also expects the Discovery Bridge's Discover rows and caches one of their covers.
enum LiveServer {
    static var env: [String: String] { ProcessInfo.processInfo.environment }
    static var configured: Bool {
        env["MA_TOKEN"]?.isEmpty == false && env["MA_URL"].flatMap(URL.init(string:)) != nil
    }
}

@Suite(.enabled(if: LiveServer.configured)) struct LiveTests {
    var client: MAClient {
        MAClient(server: URL(string: LiveServer.env["MA_URL"]!)!, token: LiveServer.env["MA_TOKEN"]!)
    }

    @Test func connectsAndBuildsASnapshotWithDiscoverCovers() async throws {
        let c = client
        try await c.connect()
        let snap = try await c.snapshot()
        await c.close()
        #expect(!snap.players.isEmpty)
        guard LiveServer.env["MA_EXPECT_DISCOVER"] == "1" else { return }
        #expect(snap.discover.count >= 10)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = SharedStore(root: dir)
        let key = try #require(snap.discover.first?.coverKey)
        await store.cacheCovers([key], server: c.server)
        #expect(store.hasCover(key))
    }

    @Test func theEventStreamStaysOpenWhileConnected() async throws {
        actor Flag { var ended = false; func set() { ended = true } }
        let c = client
        let stream = await c.events()
        try await c.connect()
        let flag = Flag()
        let reader = Task { for await _ in stream {}; await flag.set() }
        try await Task.sleep(for: .seconds(2))
        #expect(await c.isConnected)
        #expect(await flag.ended == false)          // still open after two seconds
        await c.close()
        await reader.value
        #expect(await flag.ended)                   // and ends with the connection
    }

    @Test func eventsArriveAfterAuth() async throws {
        let c = client
        let stream = await c.events()
        try await c.connect()
        _ = try await c.players()        // the connection is usable for commands while events flow
        await c.close()
        var ended = false
        for await _ in stream {}
        ended = true
        #expect(ended)
    }
}
