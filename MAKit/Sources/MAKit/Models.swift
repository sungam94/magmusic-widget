import Foundation

/// The parts of Music Assistant's answers the widget uses. Unknown keys are ignored; most fields are optional
/// because MA leaves them out or null depending on the provider.
public struct MAImage: Codable, Hashable, Sendable {
    public var type: String?
    public var path: String
    public var provider: String
    public var proxyId: String?

    enum CodingKeys: String, CodingKey { case type, path, provider, proxyId = "proxy_id" }
}

public struct MANamed: Codable, Hashable, Sendable {
    public var name: String
}

public struct MAMetadata: Codable, Hashable, Sendable {
    public var images: [MAImage]?
}

public struct MAMediaItem: Codable, Hashable, Sendable {
    public var name: String
    public var uri: String?
    public var mediaType: String?
    public var artists: [MANamed]?
    public var album: MANamed?
    public var image: MAImage?
    public var metadata: MAMetadata?

    enum CodingKeys: String, CodingKey { case name, uri, artists, album, image, metadata, mediaType = "media_type" }

    /// The thumb MA shows for the item: its own image, else the first thumb in its metadata.
    public var thumb: MAImage? {
        if let image, image.type == nil || image.type == "thumb" { return image }
        return metadata?.images?.first { $0.type == "thumb" }
    }
}

public struct MAQueueItem: Codable, Hashable, Sendable {
    public var name: String
    public var duration: Double?
    public var image: MAImage?
    public var mediaItem: MAMediaItem?

    enum CodingKeys: String, CodingKey { case name, duration, image, mediaItem = "media_item" }
}

public struct MAQueue: Codable, Hashable, Sendable {
    public var queueId: String
    public var state: String?
    public var elapsedTime: Double?
    public var elapsedTimeLastUpdated: Double?
    public var currentItem: MAQueueItem?
    public var nextItem: MAQueueItem?

    enum CodingKeys: String, CodingKey {
        case state
        case queueId = "queue_id", elapsedTime = "elapsed_time", elapsedTimeLastUpdated = "elapsed_time_last_updated"
        case currentItem = "current_item", nextItem = "next_item"
    }
}

public struct MAPlayer: Codable, Hashable, Sendable {
    public var playerId: String
    public var name: String?
    public var displayName: String?
    public var playbackState: String?
    public var volumeLevel: Int?
    public var available: Bool?
    public var enabled: Bool?
    public var hideInUi: Bool?
    public var activeSource: String?
    public var provider: String?
    public var deviceInfo: DeviceInfo?

    public struct DeviceInfo: Codable, Hashable, Sendable {
        public var ipAddress: String?
        enum CodingKeys: String, CodingKey { case ipAddress = "ip_address" }
    }

    enum CodingKeys: String, CodingKey {
        case name, available, enabled, provider, deviceInfo = "device_info"
        case playerId = "player_id", displayName = "display_name", playbackState = "playback_state"
        case volumeLevel = "volume_level", hideInUi = "hide_in_ui", activeSource = "active_source"
    }

    /// Players a person would pick: reachable, switched on in MA and not hidden there.
    public var isListed: Bool { available == true && enabled != false && hideInUi != true }
}

public struct MARecommendationRow: Codable, Hashable, Sendable {
    public var itemId: String
    public var provider: String
    public var name: String
    public var items: [MAMediaItem]?

    enum CodingKeys: String, CodingKey { case name, provider, items, itemId = "item_id" }
}
