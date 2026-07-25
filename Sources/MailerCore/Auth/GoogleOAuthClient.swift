import Foundation

/// Google OAuth 2.0 の認可 URL 生成とトークンエンドポイント呼び出し。
public struct GoogleOAuthClient: Sendable {
    public static let authorizationEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    public static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!
    public static let revocationEndpoint = URL(string: "https://oauth2.googleapis.com/revoke")!

    let configuration: OAuthConfiguration
    let transport: HTTPTransport

    public init(configuration: OAuthConfiguration, transport: HTTPTransport = URLSessionTransport()) {
        self.configuration = configuration
        self.transport = transport
    }

    /// Google の iOS クライアントが使うカスタム URL スキーム (クライアント ID の逆順表記)。
    /// 例: "123-abc.apps.googleusercontent.com" → "com.googleusercontent.apps.123-abc"
    public static func redirectScheme(forClientID clientID: String) -> String? {
        let suffix = ".apps.googleusercontent.com"
        guard clientID.hasSuffix(suffix), clientID.count > suffix.count else {
            return nil
        }
        return "com.googleusercontent.apps.\(clientID.dropLast(suffix.count))"
    }

    public func authorizationURL(
        redirectURI: String,
        pkce: PKCE,
        state: String,
        loginHint: String? = nil
    ) -> URL {
        var components = URLComponents(url: Self.authorizationEndpoint, resolvingAgainstBaseURL: false)!
        var queryItems = [
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: configuration.scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: pkce.codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            // refresh_token を確実に得るための指定。prompt=consent が無いと2回目以降の認可で発行されない。
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
        ]
        if let loginHint {
            queryItems.append(URLQueryItem(name: "login_hint", value: loginHint))
        }
        components.queryItems = queryItems
        return components.url!
    }

    public func exchangeCode(_ code: String, pkce: PKCE, redirectURI: String) async throws -> TokenResponse {
        var parameters = [
            "client_id": configuration.clientID,
            "code": code,
            "code_verifier": pkce.codeVerifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI,
        ]
        parameters["client_secret"] = configuration.clientSecret
        return try await postToTokenEndpoint(parameters: parameters)
    }

    public func refreshAccessToken(refreshToken: String) async throws -> TokenResponse {
        var parameters = [
            "client_id": configuration.clientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
        ]
        parameters["client_secret"] = configuration.clientSecret
        return try await postToTokenEndpoint(parameters: parameters)
    }

    /// トークンの失効。アカウント削除時に呼ぶ。既に失効済みでもエラーにしない (冪等)。
    public func revoke(token: String) async throws {
        var request = URLRequest(url: Self.revocationEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = URLEncodedForm.encode(["token": token])
        _ = try await transport.send(request)
    }

    private func postToTokenEndpoint(parameters: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: Self.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = URLEncodedForm.encode(parameters)
        let (data, response) = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else {
            let errorBody = try? JSONDecoder().decode(TokenErrorResponse.self, from: data)
            throw OAuthError.tokenEndpointFailed(
                statusCode: response.statusCode,
                error: errorBody?.error,
                description: errorBody?.errorDescription
            )
        }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }
}

struct TokenErrorResponse: Codable {
    let error: String?
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}
