import Foundation
import Testing
@testable import MAKit

/// Real Music Assistant 2.10 answers, anonymised by scripts/anonymize_fixtures.py (no token in them).
enum Fixture {
    static func data(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    /// The "result" of a saved reply, as the client hands it to the decoder.
    static func result(_ name: String) throws -> Data {
        try MAMessage.parse(try data(name)).result ?? Data()
    }

    static func players() throws -> [MAPlayer] { try JSONDecoder().decode([MAPlayer].self, from: try result("players_all")) }
    static func queues() throws -> [MAQueue] { try JSONDecoder().decode([MAQueue].self, from: try result("queues_all")) }
    /// Hand-written rows for the Discover filter: one row the widget does not want, and source rows with
    /// playlists both with and without the bridge's covers.
    static func filteredRows() throws -> [MARecommendationRow] {
        try JSONDecoder().decode([MARecommendationRow].self, from: try result("filtered_rows"))
    }

    static func rows() throws -> [MARecommendationRow] {
        let rows = try JSONDecoder().decode([MARecommendationRow].self, from: try result("recommendations"))
        let items = try JSONDecoder().decode([String: [MAMediaItem]].self, from: try data("recommendation_items"))
        return rows.map { row in
            var row = row
            row.items = items["\(row.provider)|\(row.itemId)"] ?? []
            return row
        }
    }
}

@Suite struct SnapshotTests {
    let now = Date(timeIntervalSince1970: 1_791_345_700)

    func snapshot() throws -> Snapshot {
        try SnapshotBuilder.build(players: Fixture.players(), queues: Fixture.queues(), rows: Fixture.rows(), now: now)
    }

    @Test func onlyAvailableEnabledVisiblePlayersAreListed() throws {
        let names = try snapshot().players.map(\.name)
        #expect(Set(names) == [Fx.wiimName, Fx.squeezeliteName, Fx.tvName, Fx.roomName])
    }

    @Test func aPlayerShowsWhatItsQueueIsPlaying() throws {
        let wiim = try #require(try snapshot().players.first { $0.name == Fx.wiimName })
        let now = try #require(wiim.nowPlaying)
        #expect(!now.title.isEmpty && !now.artist.isEmpty)
        #expect(now.coverKey != nil && (now.duration ?? 0) > 0)
        #expect(wiim.volume == 33 || wiim.volume != nil)
    }

    @Test func aPlayerKnowsItsNextTrackSoTheWidgetCanMoveOnWithoutARedraw() throws {
        var queues = try Fixture.queues()          // the saved WiiM queue was on its last track: give it a next one
        let other = try #require(queues.first { $0.queueId == Fx.squeezeliteId }?.currentItem)
        let i = try #require(queues.firstIndex { $0.queueId == Fx.wiimId })
        queues[i].nextItem = other
        let snap = SnapshotBuilder.build(players: try Fixture.players(), queues: queues, rows: [], now: now)
        let wiim = try #require(snap.players.first { $0.name == Fx.wiimName })
        let next = try #require(wiim.next)
        #expect(next.title == other.mediaItem?.name && next.elapsed == 0 && next.coverKey != nil)
        #expect(try snapshot().players.first { $0.name == Fx.wiimName }?.next == nil)   // last track: none
    }

    @Test func theNextTrackStartsWhenTheCurrentOneEnds() {
        let start = Date(timeIntervalSince1970: 1000)
        let np = NowPlaying(title: "t", artist: "a", album: nil, duration: 300, elapsed: 100, elapsedAt: start,
                            isPlaying: true, coverKey: nil, uri: nil)
        #expect(np.endDate(at: start) == start.addingTimeInterval(200))
        var paused = np
        paused.isPlaying = false
        #expect(paused.endDate(at: start) == nil)
        let next = NowPlaying(title: "n", artist: "b", album: nil, duration: 60, elapsed: 0, elapsedAt: .distantPast,
                              isPlaying: false, coverKey: nil, uri: nil).startingPlay(at: start.addingTimeInterval(200))
        #expect(next.isPlaying && next.elapsed(at: start.addingTimeInterval(230)) == 30)
    }

    @Test func elapsedRunsOnWhilePlayingAndStandsStillOtherwise() {
        let start = Date(timeIntervalSince1970: 1000)
        var np = NowPlaying(title: "t", artist: "a", album: nil, duration: 300, elapsed: 20, elapsedAt: start,
                            isPlaying: true, coverKey: nil, uri: nil)
        #expect(np.elapsed(at: start.addingTimeInterval(10)) == 30)
        #expect(np.elapsed(at: start.addingTimeInterval(1000)) == 300)        // never past the end
        np.isPlaying = false
        #expect(np.elapsed(at: start.addingTimeInterval(10)) == 20)
    }

    @Test func theActivePlayerIsTheChosenOneElseOnePlayingElseTheMostRecent() throws {
        var snap = try snapshot()
        #expect(snap.activePlayer(preferred: Fx.squeezeliteId)?.name == Fx.squeezeliteName)
        #expect(snap.activePlayer(preferred: "gone")?.name == Fx.wiimName)  // most recently active of the idle ones
        snap.players = snap.players.map { p in
            var p = p
            if p.name == Fx.tvName { p.state = .playing }
            return p
        }
        #expect(snap.activePlayer(preferred: nil)?.name == Fx.tvName)
    }

    @Test func discoverListsOurPlaylistsWithTheirCovers() throws {
        let discover = try snapshot().discover
        #expect(discover.count >= 10)
        #expect(discover.allSatisfy { $0.coverKey != nil && $0.uri.contains("://playlist/") })
        #expect(discover.contains { $0.name.hasPrefix("Spotify · ") })
        #expect(discover.contains { $0.uri.hasPrefix("tidal") || $0.uri.hasPrefix("soundcloud") })
        #expect(Set(discover.map(\.uri)).count == discover.count)
    }

    @Test func aRowNotNamedInTheSourceRowsIsLeftOut() throws {
        let rows = try Fixture.filteredRows()
        let other = try #require(rows.first { $0.name == "Popular playlists" })
        #expect(!SnapshotBuilder.wantsRow(other))
        #expect(rows.filter { $0.name != other.name }.allSatisfy(SnapshotBuilder.wantsRow))
        let discover = SnapshotBuilder.build(players: [], queues: [], rows: rows, now: now).discover
        #expect(!discover.contains { $0.row == other.name })
    }

    @Test func aTidalOrSoundCloudPlaylistWithoutOurCoverIsLeftOut() throws {
        let discover = SnapshotBuilder.build(players: [], queues: [], rows: try Fixture.filteredRows(), now: now).discover
        #expect(Set(discover.map(\.name)) == ["TIDAL mix with our cover", "SoundCloud playlist with our cover"])
    }

    @Test func onlyTheChosenSpeakersAreListedEvenOneHiddenInMA() throws {
        let local = Fx.localId                                     // this Mac: hidden in MA's own UI
        let snap = SnapshotBuilder.build(players: try Fixture.players(), queues: try Fixture.queues(), rows: [], now: now,
                                         speakers: [Fx.wiimId, Fx.squeezeliteId, local],
                                         localId: local)
        #expect(Set(snap.players.map(\.name)) == [Fx.wiimName, Fx.squeezeliteName, "This Mac"])
    }

    @Test func thisMacIsThePlayerAtOneOfItsAddresses() throws {
        #expect(SnapshotBuilder.localPlayer(try Fixture.players(), localAddresses: [Fx.localIP]) == Fx.localId)
        #expect(SnapshotBuilder.localPlayer(try Fixture.players(), localAddresses: ["127.0.0.1"]) == nil)
    }

    @Test func theDefaultSpeakersAreAllListedPlayersAndThisMac() throws {
        let players = try Fixture.players()
        let listed = players.filter(\.isListed).map(\.playerId)
        let ids = SnapshotBuilder.defaultSpeakers(players, localAddresses: [Fx.localIP, "127.0.0.1"])
        #expect(ids == listed + [Fx.localId])
        #expect(Set(ids) == [Fx.wiimId, Fx.squeezeliteId, Fx.tvId, Fx.roomId, Fx.localId])
        let unlisted = SnapshotBuilder.defaultSpeakers(players, localAddresses: ["127.0.0.1"])
        #expect(unlisted == listed)                              // no local player found: the listed ones only
        var shown = players
        let i = try #require(shown.firstIndex { $0.playerId == Fx.localId })
        shown[i].hideInUi = false                                // this Mac shown in MA as well: listed once
        #expect(SnapshotBuilder.defaultSpeakers(shown, localAddresses: [Fx.localIP]).filter { $0 == Fx.localId }.count == 1)
    }

    @Test func theNextSpeakerGoesByNameAndWrapsAround() throws {
        let snap = try snapshot()
        let names = snap.players.map(\.name).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        let ids = names.map { n in snap.players.first { $0.name == n }!.id }
        #expect(snap.speaker(after: ids[0]) == ids[1])
        #expect(snap.speaker(after: ids.last!) == ids[0])
        #expect(snap.speaker(after: "gone") == ids[0])
    }

    @Test func discoverTakesOnePlaylistFromEachRowInTurn() throws {
        let discover = try snapshot().discover
        let firstRows = discover.prefix(4).map(\.row)
        #expect(Set(firstRows).count >= 3)                     // the first covers come from different rows
        var seenRows: [String] = []
        for item in discover where !seenRows.contains(item.row) { seenRows.append(item.row) }
        #expect(Array(discover.prefix(seenRows.count).map(\.row)) == seenRows)
    }

    @Test func aSnapshotSurvivesTheRoundTripThroughTheSharedFile() throws {
        let snap = try snapshot()
        let back = try JSONDecoder.ma.decode(Snapshot.self, from: try JSONEncoder.ma.encode(snap))
        #expect(back == snap)
    }
}
