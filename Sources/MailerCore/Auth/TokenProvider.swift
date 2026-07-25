import Foundation

/// アカウントごとに有効なアクセストークンを供給する。期限切れならリフレッシュして永続化する。
public actor TokenProvider {
    private let oauth: GoogleOAuthClient
    private let tokenStore: TokenStore
    private var refreshTasks: [String: Task<StoredToken, Error>] = [:]

    public init(oauth: GoogleOAuthClient, tokenStore: TokenStore) {
        self.oauth = oauth
        self.tokenStore = tokenStore
    }

    public func accessToken(for email: String) async throws -> String {
        try await validToken(for: email).accessToken
    }

    /// 401 を受けた後などに、期限に関わらず強制リフレッシュする。
    public func refreshedAccessToken(for email: String) async throws -> String {
        guard let token = try tokenStore.load(for: email) else {
            throw OAuthError.notAuthorized(email: email)
        }
        return try await refresh(token, for: email).accessToken
    }

    private func validToken(for email: String) async throws -> StoredToken {
        guard let token = try tokenStore.load(for: email) else {
            throw OAuthError.notAuthorized(email: email)
        }
        guard token.isExpired() else {
            return token
        }
        return try await refresh(token, for: email)
    }

    /// 同一アカウントへの並行リフレッシュを1つの Task に束ねる。
    private func refresh(_ token: StoredToken, for email: String) async throws -> StoredToken {
        if let running = refreshTasks[email] {
            return try await running.value
        }
        let task = Task<StoredToken, Error> {
            let response = try await oauth.refreshAccessToken(refreshToken: token.refreshToken)
            let refreshed = token.refreshed(with: response)
            try tokenStore.save(refreshed, for: email)
            return refreshed
        }
        refreshTasks[email] = task
        defer { refreshTasks[email] = nil }
        return try await task.value
    }
}
