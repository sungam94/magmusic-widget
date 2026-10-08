import Foundation

public enum MAError: Error, Equatable, Sendable {
    case server(code: Int, details: String)
    case notConnected
    case timeout(String)
    case badMessage
    case notConfigured
}

/// A JSON value for command arguments; literals make call sites read like the JSON they send.
public enum JSONValue: Sendable, Hashable, ExpressibleByStringLiteral, ExpressibleByIntegerLiteral,
    ExpressibleByFloatLiteral, ExpressibleByBooleanLiteral, ExpressibleByNilLiteral {
    case string(String), int(Int), double(Double), bool(Bool), array([JSONValue]), null

    public init(stringLiteral value: String) { self = .string(value) }
    public init(integerLiteral value: Int) { self = .int(value) }
    public init(floatLiteral value: Double) { self = .double(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(nilLiteral: ()) { self = .null }

    var any: Any {
        switch self {
        case .string(let s): s
        case .int(let i): i
        case .double(let d): d
        case .bool(let b): b
        case .array(let a): a.map(\.any)
        case .null: NSNull()
        }
    }
}

/// One message from MA's WebSocket: a reply (message_id, result or error) or an event.
public struct MAMessage: Sendable {
    public var messageId: String?
    public var event: String?
    public var objectId: String?
    public var result: Data?
    public var error: MAError?

    public static func parse(_ data: Data) throws -> MAMessage {
        guard let obj = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? [String: Any] else {
            throw MAError.badMessage
        }
        var msg = MAMessage()
        if let id = obj["message_id"] { msg.messageId = "\(id)" }
        msg.event = obj["event"] as? String
        msg.objectId = obj["object_id"] as? String
        if let code = obj["error_code"] as? Int {
            msg.error = .server(code: code, details: obj["details"] as? String ?? "")
        } else if let result = obj["result"], !(result is NSNull) {
            msg.result = try JSONSerialization.data(withJSONObject: result, options: [.fragmentsAllowed])
        }
        return msg
    }

    public static func command(id: String, _ command: String, _ args: [String: JSONValue]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["message_id": id, "command": command,
                                                    "args": args.mapValues(\.any)])
    }
}
