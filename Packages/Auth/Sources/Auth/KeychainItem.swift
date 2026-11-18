import Foundation
import Security

public struct KeychainError: LocalizedError, Sendable {
    public let status: OSStatus

    public var errorDescription: String? {
        (SecCopyErrorMessageString(status, nil) as String?) ?? "Keychain error \(status)"
    }
}

protocol KeychainStore: Sendable {
    func read() throws(KeychainError) -> Data?
    func write(_ data: Data) throws(KeychainError)
    func delete() throws(KeychainError)
}

struct KeychainItem: KeychainStore {
    let service: String
    let account: String

    static let session = KeychainItem(service: "dev.kruhlyk.tunewave.session", account: "default")

    private var query: [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account]
    }

    func read() throws(KeychainError) -> Data? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query.merging([kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne]) { $1 } as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
        return result as? Data
    }

    func write(_ data: Data) throws(KeychainError) {
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging([kSecValueData: data]) { $1 } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    func delete() throws(KeychainError) {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }
}
