import Foundation
import Testing
@testable import MAKit

/// The shape of the saved Music Assistant answers that the other tests rely on: counts and structure only,
/// so the fixtures can be rewritten (for example anonymised) without the other tests losing their meaning.
@Suite struct FixtureShapeTests {
    static func json(_ name: String) throws -> Any {
        try JSONSerialization.jsonObject(with: try Fixture.data(name))
    }

    static func result(_ name: String) throws -> [[String: Any]] {
        let object = try #require(try json(name) as? [String: Any])
        return try #require(object["result"] as? [[String: Any]])
    }

    static func isMacShaped(_ id: String) -> Bool {
        id.range(of: "^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$", options: .regularExpression) != nil
    }

    @Test func fixtureShapesTheTestsDependOn() throws {
        let players = try Self.result("players_all")
        let queues = try Self.result("queues_all")
        let rows = try Self.result("recommendations")
        let items = try #require(try Self.json("recommendation_items") as? [String: [[String: Any]]])

        // Players: how many, how many are listed, and the few special ones the tests pick out.
        #expect(players.count == 16)
        #expect(try Fixture.players().count == 16)
        #expect(try Fixture.players().filter(\.isListed).count == 4)
        let hiddenLocal = players.filter { p in
            p["available"] as? Bool == true && p["hide_in_ui"] as? Bool == true
                && (p["device_info"] as? [String: Any])?["ip_address"] as? String == Fx.localIP
        }
        #expect(hiddenLocal.count == 1)
        #expect(players.filter { $0["provider"] as? String == "wiim" }.count == 1)
        #expect(players.filter { Self.isMacShaped($0["player_id"] as? String ?? "") }.count == 1)

        // The most recently active queue with a track is unique, and its player is the idle WiiM-provider one.
        let withTrack = queues.filter { $0["current_item"] is [String: Any] }
        let stamps = withTrack.compactMap { $0["elapsed_time_last_updated"] as? Double }
        let latest = try #require(stamps.max())
        let newest = withTrack.filter { $0["elapsed_time_last_updated"] as? Double == latest }
        #expect(newest.count == 1)
        let newestPlayer = try #require(players.first { $0["player_id"] as? String == newest.first?["queue_id"] as? String })
        #expect(newestPlayer["playback_state"] as? String == "idle")
        #expect(newestPlayer["provider"] as? String == "wiim")

        // Recommendation rows: eight, with these item counts in this order.
        #expect(rows.count == 8)
        let counts = rows.map { row in items["\(row["provider"] as? String ?? "")|\(row["item_id"] as? String ?? "")"]?.count ?? 0 }
        #expect(counts == [6, 6, 6, 6, 6, 6, 6, 2])

        // Every player id that another field points at exists.
        let ids = Set(players.compactMap { $0["player_id"] as? String })
        var referenced: [String] = []
        for p in players {
            for key in ["active_source", "synced_to"] { if let id = p[key] as? String { referenced.append(id) } }
            for key in ["group_members", "can_group_with"] { referenced += p[key] as? [String] ?? [] }
        }
        for q in queues {
            if let id = q["queue_id"] as? String { referenced.append(id) }
            for key in ["current_item", "next_item"] {
                if let id = (q[key] as? [String: Any])?["queue_id"] as? String { referenced.append(id) }
            }
        }
        #expect(!referenced.isEmpty)
        #expect(referenced.filter { !ids.contains($0) } == [])

        // Every saved list of row items belongs to a row.
        let rowKeys = Set(rows.map { "\($0["provider"] as? String ?? "")|\($0["item_id"] as? String ?? "")" })
        #expect(Set(items.keys).subtracting(rowKeys) == [])
    }
}
