import Foundation
import Security

struct KeychainStore: Sendable {
    let service = "org.openhome.app"

    private var accessGroup: String? {
        Bundle.main.object(forInfoDictionaryKey: "OpenHomeKeychainAccessGroup") as? String
    }

    private func query(account: String, shared: Bool = true) -> [String: Any] {
        var value: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        if shared, let accessGroup { value[kSecAttrAccessGroup as String] = accessGroup }
        return value
    }

    func save(_ value: Data, account: String) throws {
        let query = query(account: account)
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = value
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        if status == errSecMissingEntitlement, accessGroup != nil {
            var localItem = self.query(account: account, shared: false)
            SecItemDelete(localItem as CFDictionary)
            localItem[kSecValueData as String] = value
            localItem[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(localItem as CFDictionary, nil) == errSecSuccess else { throw KeychainError.writeFailed }
            return
        }
        guard status == errSecSuccess else { throw KeychainError.writeFailed }
    }

    func read(account: String) throws -> Data? {
        var query = query(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if (status == errSecItemNotFound || status == errSecMissingEntitlement), accessGroup != nil {
            var legacy = self.query(account: account, shared: false)
            legacy[kSecReturnData as String] = true
            legacy[kSecMatchLimit as String] = kSecMatchLimitOne
            let legacyStatus = SecItemCopyMatching(legacy as CFDictionary, &result)
            if legacyStatus == errSecSuccess, let data = result as? Data {
                if status == errSecItemNotFound {
                    try save(data, account: account)
                    SecItemDelete(self.query(account: account, shared: false) as CFDictionary)
                }
                return data
            }
            if legacyStatus == errSecItemNotFound { return nil }
            throw KeychainError.readFailed
        }
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.readFailed }
        return result as? Data
    }

    func delete(account: String) throws {
        let query = query(account: account)
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecMissingEntitlement, accessGroup != nil {
            let localStatus = SecItemDelete(self.query(account: account, shared: false) as CFDictionary)
            guard localStatus == errSecSuccess || localStatus == errSecItemNotFound else { throw KeychainError.writeFailed }
            return
        }
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError.writeFailed }
    }
}

enum KeychainError: LocalizedError {
    case writeFailed, readFailed
    var errorDescription: String? { self == .readFailed ? "无法读取安全存储" : "无法更新安全存储" }
}
