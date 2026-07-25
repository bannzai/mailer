import Foundation

/// アカウント (メールアドレス) 単位のトークン永続化。
public protocol TokenStore: Sendable {
    func save(_ token: StoredToken, for email: String) throws
    func load(for email: String) throws -> StoredToken?
    func delete(for email: String) throws
}

/// テスト用のインメモリ実装。
public final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: [String: StoredToken] = [:]

    public init() {}

    public func save(_ token: StoredToken, for email: String) {
        lock.withLock { tokens[email] = token }
    }

    public func load(for email: String) -> StoredToken? {
        lock.withLock { tokens[email] }
    }

    public func delete(for email: String) {
        lock.withLock { tokens[email] = nil }
    }
}
