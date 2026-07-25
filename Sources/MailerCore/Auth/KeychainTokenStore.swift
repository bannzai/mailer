import Foundation
import Security

public struct KeychainError: Error, LocalizedError, Equatable {
    public let status: OSStatus
    public let operation: String

    public var errorDescription: String? {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
        return "Keychain \(operation) に失敗しました: \(message)"
    }
}

/// Keychain (generic password) にトークンを保存する。CLI と macOS アプリで共有する。
public struct KeychainTokenStore: TokenStore {
    public static let defaultService = "com.bannzai.mailer.token"

    let service: String

    public init(service: String = Self.defaultService) {
        self.service = service
    }

    public func save(_ token: StoredToken, for email: String) throws {
        let data = try JSONEncoder().encode(token)
        var query = baseQuery(email: email)
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            query[kSecValueData as String] = data
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError(status: addStatus, operation: "add")
            }
        } else if updateStatus != errSecSuccess {
            throw KeychainError(status: updateStatus, operation: "update")
        }
    }

    public func load(for email: String) throws -> StoredToken? {
        var query = baseQuery(email: email)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError(status: status, operation: "load")
        }
        return try JSONDecoder().decode(StoredToken.self, from: data)
    }

    public func delete(for email: String) throws {
        let status = SecItemDelete(baseQuery(email: email) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status, operation: "delete")
        }
    }

    private func baseQuery(email: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: email,
        ]
    }
}
