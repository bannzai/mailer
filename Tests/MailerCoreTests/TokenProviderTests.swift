import Foundation
import Testing

@testable import MailerCore

private let refreshResponseJSON = """
    {"access_token": "at-refreshed", "expires_in": 3599, "token_type": "Bearer"}
    """

@Test func tokenProviderReturnsStoredTokenWhileValid() async throws {
    let store = InMemoryTokenStore()
    store.save(
        StoredToken(accessToken: "at-valid", refreshToken: "rt", expiresAt: Date().addingTimeInterval(3600)),
        for: "a@example.com"
    )
    let transport = MockTransport { _ in
        Issue.record("有効期限内はトークンエンドポイントを呼ばない")
        throw URLError(.badURL)
    }
    let provider = TokenProvider(
        oauth: GoogleOAuthClient(configuration: OAuthConfiguration(clientID: "c"), transport: transport),
        tokenStore: store
    )
    let token = try await provider.accessToken(for: "a@example.com")
    #expect(token == "at-valid")
}

@Test func tokenProviderRefreshesExpiredTokenAndPersists() async throws {
    let store = InMemoryTokenStore()
    store.save(
        StoredToken(accessToken: "at-expired", refreshToken: "rt", expiresAt: Date().addingTimeInterval(-10)),
        for: "a@example.com"
    )
    let transport = MockTransport { request in
        (Data(refreshResponseJSON.utf8), httpResponse(url: request.url!, statusCode: 200))
    }
    let provider = TokenProvider(
        oauth: GoogleOAuthClient(configuration: OAuthConfiguration(clientID: "c"), transport: transport),
        tokenStore: store
    )
    let token = try await provider.accessToken(for: "a@example.com")
    #expect(token == "at-refreshed")
    #expect(store.load(for: "a@example.com")?.accessToken == "at-refreshed")
    #expect(store.load(for: "a@example.com")?.refreshToken == "rt")
}

@Test func tokenProviderThrowsForUnknownAccount() async throws {
    let provider = TokenProvider(
        oauth: GoogleOAuthClient(
            configuration: OAuthConfiguration(clientID: "c"),
            transport: MockTransport { _ in throw URLError(.badURL) }
        ),
        tokenStore: InMemoryTokenStore()
    )
    await #expect(throws: OAuthError.notAuthorized(email: "nobody@example.com")) {
        _ = try await provider.accessToken(for: "nobody@example.com")
    }
}
