import Foundation

/// users.getProfile のレスポンス。
public struct GmailProfile: Codable, Sendable, Equatable {
    public let emailAddress: String
    public let messagesTotal: Int?
    public let threadsTotal: Int?
    public let historyId: String?
}

/// 認可直後にアカウントのメールアドレスを解決するための最小限のクライアント。
public struct ProfileClient: Sendable {
    static let profileURL = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/profile")!

    let transport: HTTPTransport

    public init(transport: HTTPTransport = URLSessionTransport()) {
        self.transport = transport
    }

    public func fetch(accessToken: String) async throws -> GmailProfile {
        var request = URLRequest(url: Self.profileURL)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw OAuthError.tokenEndpointFailed(
                statusCode: response.statusCode,
                error: "users.getProfile failed",
                description: String(decoding: data, as: UTF8.self)
            )
        }
        return try JSONDecoder().decode(GmailProfile.self, from: data)
    }
}
