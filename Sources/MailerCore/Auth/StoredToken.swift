import Foundation

/// トークンエンドポイントのレスポンス。
public struct TokenResponse: Codable, Sendable, Equatable {
    public let accessToken: String
    public let expiresIn: Int
    public let refreshToken: String?
    public let scope: String?
    public let tokenType: String?
    public let idToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
        case tokenType = "token_type"
        case idToken = "id_token"
    }
}

/// Keychain に永続化するアカウント単位のトークン。
public struct StoredToken: Codable, Sendable, Equatable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date
    public var scope: String?

    public init(accessToken: String, refreshToken: String, expiresAt: Date, scope: String? = nil) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.scope = scope
    }

    /// 初回認可のレスポンスから生成する。refresh_token が無い場合は認可のやり直しが必要。
    public init(response: TokenResponse, now: Date = Date()) throws {
        guard let refreshToken = response.refreshToken else {
            throw OAuthError.missingRefreshToken
        }
        self.init(
            accessToken: response.accessToken,
            refreshToken: refreshToken,
            expiresAt: now.addingTimeInterval(TimeInterval(response.expiresIn)),
            scope: response.scope
        )
    }

    /// リフレッシュ結果を反映する。レスポンスに refresh_token が無ければ既存の値を維持する。
    public func refreshed(with response: TokenResponse, now: Date = Date()) -> StoredToken {
        StoredToken(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken ?? refreshToken,
            expiresAt: now.addingTimeInterval(TimeInterval(response.expiresIn)),
            scope: response.scope ?? scope
        )
    }

    public func isExpired(now: Date = Date(), leeway: TimeInterval = 60) -> Bool {
        now.addingTimeInterval(leeway) >= expiresAt
    }
}
