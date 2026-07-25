import Foundation

/// 登録済みアカウント。トークン本体は TokenStore (Keychain) 側に持つ。
public struct AccountRecord: Codable, Sendable, Equatable, Identifiable {
    public var email: String
    public var addedAt: Date

    public var id: String { email }

    public init(email: String, addedAt: Date = Date()) {
        self.email = email
        self.addedAt = addedAt
    }
}

public struct AccountList: Codable, Sendable, Equatable {
    public var defaultAccount: String?
    public var accounts: [AccountRecord]

    public init(defaultAccount: String? = nil, accounts: [AccountRecord] = []) {
        self.defaultAccount = defaultAccount
        self.accounts = accounts
    }
}

public enum AccountStoreError: Error, LocalizedError, Equatable {
    case unknownAccount(String)

    public var errorDescription: String? {
        switch self {
        case .unknownAccount(let email):
            return "アカウント \(email) は登録されていません。"
        }
    }
}

/// アカウント一覧と既定アカウントを accounts.json に永続化する。CLI とアプリで共有する。
public struct AccountStore: Sendable {
    let fileURL: URL

    public init(directory: URL = MailerPaths.configDirectory) {
        self.fileURL = directory.appendingPathComponent("accounts.json")
    }

    public func load() throws -> AccountList {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return AccountList()
        }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AccountList.self, from: data)
    }

    public func save(_ list: AccountList) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(list).write(to: fileURL, options: .atomic)
    }

    /// アカウントを追加する。登録済みなら何もしない (冪等)。最初の1件は既定アカウントになる。
    @discardableResult
    public func add(email: String, now: Date = Date()) throws -> AccountRecord {
        var list = try load()
        if let existing = list.accounts.first(where: { $0.email == email }) {
            return existing
        }
        let record = AccountRecord(email: email, addedAt: now)
        list.accounts.append(record)
        if list.defaultAccount == nil {
            list.defaultAccount = email
        }
        try save(list)
        return record
    }

    /// アカウントを削除する。既定アカウントを消した場合は残りの先頭を既定に繰り上げる。
    public func remove(email: String) throws {
        var list = try load()
        list.accounts.removeAll { $0.email == email }
        if list.defaultAccount == email {
            list.defaultAccount = list.accounts.first?.email
        }
        try save(list)
    }

    public func setDefault(email: String) throws {
        var list = try load()
        guard list.accounts.contains(where: { $0.email == email }) else {
            throw AccountStoreError.unknownAccount(email)
        }
        list.defaultAccount = email
        try save(list)
    }

    /// --account 未指定時に使うアカウントを解決する。
    public func resolveAccount(_ explicit: String?) throws -> String {
        let list = try load()
        if let explicit {
            guard list.accounts.contains(where: { $0.email == explicit }) else {
                throw AccountStoreError.unknownAccount(explicit)
            }
            return explicit
        }
        guard let defaultAccount = list.defaultAccount else {
            throw OAuthError.notAuthorized(email: "(未登録)")
        }
        return defaultAccount
    }
}
