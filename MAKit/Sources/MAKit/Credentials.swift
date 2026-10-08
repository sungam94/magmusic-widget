import Foundation
import Security

/// The MA token in the keychain, shared with the widget through a keychain access group ("MAKeychainGroup" in
/// Info.plist). Never written to files or logs.
public enum Credentials {
    static let service = "magmusic.musicassistant"
    static let account = "token"

    static var group: String? { Bundle.main.object(forInfoDictionaryKey: "MAKeychainGroup") as? String }

    /// Signed builds use the data protection keychain with the shared access group; an unsigned development
    /// build has no entitlements for it and falls back to the login keychain (app only).
    static func query(shared: Bool) -> [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service, kSecAttrAccount as String: account]
        if shared {
            q[kSecUseDataProtectionKeychain as String] = true
            if let group, !group.isEmpty, !group.hasPrefix("$") { q[kSecAttrAccessGroup as String] = group }
        }
        return q
    }

    public static var token: String? {
        for shared in [true, false] {
            var q = query(shared: shared)
            q[kSecReturnData as String] = true
            q[kSecMatchLimit as String] = kSecMatchLimitOne
            var out: CFTypeRef?
            if SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data {
                return String(data: data, encoding: .utf8)
            }
        }
        return nil
    }

    @discardableResult
    public static func save(_ token: String) -> Bool {
        for shared in [true, false] {
            SecItemDelete(query(shared: shared) as CFDictionary)
            var q = query(shared: shared)
            q[kSecValueData as String] = Data(token.utf8)
            q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let status = SecItemAdd(q as CFDictionary, nil)
            if status == errSecSuccess { return true }
            if status != errSecMissingEntitlement { return false }
        }
        return false
    }

    /// A client for the saved server and token, or nil before the app is set up.
    public static func client(_ store: SharedStore = SharedStore()) -> MAClient? {
        guard let server = store.server, let token, !token.isEmpty else { return nil }
        return MAClient(server: server, token: token)
    }
}
