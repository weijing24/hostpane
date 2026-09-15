import Foundation
import Security

public enum SecretStoreError: Error, LocalizedError {
    case unexpectedStatus(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            if let message = SecCopyErrorMessageString(status, nil) as String? {
                return message
            }
            return "Keychain status \(status)"
        }
    }
}

public struct SecretStore: Sendable {
    public static let service = "eu.jimwei.hostpane"

    public init() {}

    public func passwordAccount(for hostID: UUID) -> String {
        "host.\(hostID.uuidString).password"
    }

    public func passphraseAccount(for hostID: UUID) -> String {
        "host.\(hostID.uuidString).key-passphrase"
    }

    public func keyPassphraseAccount(for keyID: UUID) -> String {
        "key.\(keyID.uuidString).passphrase"
    }

    public func set(_ secret: String, account: String) throws {
        let payload = Data(secret.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: payload,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecSuccess {
            let update = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            guard update == errSecSuccess else { throw SecretStoreError.unexpectedStatus(update) }
            return
        }
        if status == errSecItemNotFound {
            var add = query
            add.merge(attributes) { _, new in new }
            let added = SecItemAdd(add as CFDictionary, nil)
            guard added == errSecSuccess else { throw SecretStoreError.unexpectedStatus(added) }
            return
        }
        throw SecretStoreError.unexpectedStatus(status)
    }

    public func get(account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else { throw SecretStoreError.unexpectedStatus(status) }
        guard let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound {
            return
        }
        throw SecretStoreError.unexpectedStatus(status)
    }
}
