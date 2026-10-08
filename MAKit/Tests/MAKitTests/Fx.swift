/// The fixture values the tests refer to by name, so that changing the fixtures changes only this file.
enum Fx {
    /// The address the tests pass as this Mac's own; the hidden local player in the fixtures has it.
    static let localIP = "192.0.2.104"
    /// This Mac's player: available, hidden in MA's own UI, at `localIP`.
    static let localId = "up0000000004"
    /// The one player of the "wiim" provider; its queue is the most recently active one with a track.
    static let wiimId = "wiim_uuid:00000000-0000-0000-0000-000000000012"
    /// The one player with a MAC-shaped id (a squeezelite player).
    static let squeezeliteId = "02:00:00:00:00:0b"
    /// The other two listed players: an AirPlay TV and a universal player.
    static let tvId = "ap02000000000f"
    static let roomId = "up0000000002"

    /// The names of the four players MA lists.
    static let wiimName = "Basement WiiM"
    static let squeezeliteName = "Guest Room HiFiBerry"
    static let tvName = "Workshop"
    static let roomName = "Kitchen"
}
