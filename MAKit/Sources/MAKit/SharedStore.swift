import Foundation

/// The container the menu bar app and the widget share: the snapshot, the cached covers and the settings.
/// The app group comes from the bundle's Info.plist ("MAAppGroup"); unsigned development builds without one
/// fall back to Application Support, which only the app itself can read.
public struct SharedStore: Sendable {
    public let root: URL
    public let groupId: String?

    public init(groupId: String? = Bundle.main.object(forInfoDictionaryKey: "MAAppGroup") as? String) {
        self.groupId = groupId
        let group = Self.usable(groupId).flatMap { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
        let fallback = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MagMusicWidget", isDirectory: true)
        root = group ?? fallback
        try? FileManager.default.createDirectory(at: root.appendingPathComponent("covers"), withIntermediateDirectories: true)
    }

    public init(root: URL) {
        self.root = root
        groupId = nil
        try? FileManager.default.createDirectory(at: root.appendingPathComponent("covers"), withIntermediateDirectories: true)
    }

    /// An unsigned build leaves the group setting unexpanded ("$(TeamIdentifierPrefix)…") or empty.
    static func usable(_ group: String?) -> String? {
        guard let group, !group.isEmpty, !group.hasPrefix("$"), !group.hasPrefix(".") else { return nil }
        return group
    }

    var snapshotFile: URL { root.appendingPathComponent("snapshot.json") }

    public func load() -> Snapshot {
        guard let data = try? Data(contentsOf: snapshotFile) else { return .empty }
        return (try? JSONDecoder.ma.decode(Snapshot.self, from: data)) ?? .empty
    }

    public func save(_ snapshot: Snapshot) throws {
        try JSONEncoder.ma.encode(snapshot).write(to: snapshotFile, options: .atomic)
    }

    public static func coverURL(server: URL, key: String, size: Int) -> URL {
        var parts = URLComponents(url: server, resolvingAgainstBaseURL: false)!
        parts.path = "/imageproxy/\(key)"
        parts.queryItems = [URLQueryItem(name: "size", value: String(size))]
        return parts.url!
    }

    public func coverFile(_ key: String) -> URL { root.appendingPathComponent("covers/\(key).jpg") }

    public func hasCover(_ key: String) -> Bool { FileManager.default.fileExists(atPath: coverFile(key).path) }

    /// Downloads the covers not cached yet; MA's proxy ids change with the image, so a cached one never goes stale.
    public func cacheCovers(_ keys: [String], server: URL, size: Int = 512) async {   // MA serves 0, 80, 160, 256, 512, 1024
        for key in Set(keys) where !hasCover(key) {
            guard let (data, response) = try? await URLSession.shared.data(from: Self.coverURL(server: server, key: key, size: size)),
                  (response as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty else { continue }
            try? data.write(to: coverFile(key), options: .atomic)
        }
    }

    /// Covers no longer in the snapshot are removed, so the folder does not grow forever.
    public func pruneCovers(keeping keys: Set<String>) {
        let dir = root.appendingPathComponent("covers")
        for file in (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        where !keys.contains(file.deletingPathExtension().lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    public func coverKeys(_ snapshot: Snapshot) -> [String] {
        snapshot.players.flatMap { [$0.nowPlaying?.coverKey, $0.next?.coverKey].compactMap { $0 } }
            + snapshot.discover.compactMap(\.coverKey)
    }

    // MARK: settings shared with the widget

    var defaults: UserDefaults {
        Self.usable(groupId).flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    public var server: URL? {
        get { defaults.string(forKey: "server").flatMap(URL.init(string:)) }
        nonmutating set { defaults.set(newValue?.absoluteString, forKey: "server") }
    }

    /// The speakers shown, in MA player ids; nil until set (then the app picks the defaults).
    public var speakers: [String]? {
        get { defaults.stringArray(forKey: "speakers") }
        nonmutating set { defaults.set(newValue, forKey: "speakers") }
    }

    /// The MA player that is this Mac, named "This Mac".
    public var localPlayer: String? {
        get { defaults.string(forKey: "localPlayer") }
        nonmutating set { defaults.set(newValue, forKey: "localPlayer") }
    }

    public var preferredPlayer: String? {
        get { defaults.string(forKey: "preferredPlayer") }
        nonmutating set { defaults.set(newValue, forKey: "preferredPlayer") }
    }
}
