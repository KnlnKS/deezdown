import Foundation
import Security

/// The ARL signs in as the account, so it lives in the login keychain, one per config folder.
/// Each call runs off the caller's actor, since a keychain access prompt blocks until answered.
public struct CredentialStore: Sendable {
    private let account: String

    public init(paths: AppPaths) {
        account = paths.configDirectory.path(percentEncoded: false)
    }

    private var item: [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: "deezdown", kSecAttrAccount: account]
    }

    @concurrent
    public func arl() async -> String? {
        var result: CFTypeRef?
        let query = item.merging([kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne]) { $1 }
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data
        else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// Updates in place rather than replacing, so apps already allowed to read the item keep access.
    @concurrent
    public func save(arl: String) async throws {
        let value: [CFString: Any] = [kSecValueData: Data(arl.utf8)]
        var status = SecItemUpdate(item as CFDictionary, value as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(item.merging(value) { $1 } as CFDictionary, nil)
        }
        try check(status)
    }

    @concurrent
    public func clear() async throws {
        let status = SecItemDelete(item as CFDictionary)
        try check(status == errSecItemNotFound ? errSecSuccess : status)
    }

    private func check(_ status: OSStatus) throws {
        guard status != errSecSuccess else { return }
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)."
        throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey: message])
    }
}
