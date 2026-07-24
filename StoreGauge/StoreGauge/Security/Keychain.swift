//
//  Keychain.swift
//  StoreGauge
//
//  Minimal wrapper around the Keychain for store-provider secret payloads.
//  Apple currently stores its .p8 key; Google will store service-account/OAuth
//  material under the same stable per-account lookup.
//

import Foundation
import Security

enum Keychain {
    static let service = "com.bazun.storegauge.asc-private-key"

    enum KeychainError: LocalizedError {
        case status(OSStatus)
        case invalidData
        case verificationFailed

        var errorDescription: String? {
            switch self {
            case .status(let s):
                let msg = SecCopyErrorMessageString(s, nil) as String? ?? "OSStatus \(s)"
                return "Keychain error: \(msg)"
            case .invalidData:
                return "The saved Keychain item could not be read as text."
            case .verificationFailed:
                return "The credential could not be verified after saving it to Keychain."
            }
        }
    }

    @discardableResult
    static func save(_ value: String, account: String) throws -> Bool {
        let data = Data(value.utf8)
        let match: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let updateStatus = SecItemUpdate(match as CFDictionary, attributes as CFDictionary)
        let status: OSStatus
        if updateStatus == errSecItemNotFound {
            var item = match
            attributes.forEach { item[$0.key] = $0.value }
            status = SecItemAdd(item as CFDictionary, nil)
        } else {
            status = updateStatus
        }

        guard status == errSecSuccess else { throw KeychainError.status(status) }
        guard try loadThrowing(account: account) == value else {
            throw KeychainError.verificationFailed
        }
        return true
    }

    static func load(account: String) -> String? {
        try? loadThrowing(account: account)
    }

    private static func loadThrowing(account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.status(status) }
        guard let data = item as? Data,
              let value = String(data: data, encoding: .utf8)
        else {
            throw KeychainError.invalidData
        }
        return value
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
