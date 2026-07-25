import Foundation
import Testing

@testable import MailerCore

private let configuration = OAuthConfiguration(clientID: "client-123", clientSecret: "secret-abc")

private func queryItems(of url: URL) -> [String: String] {
    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
    return Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
}

@Test func authorizationURLContainsRequiredParameters() {
    let client = GoogleOAuthClient(configuration: configuration)
    let pkce = PKCE(codeVerifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
    let url = client.authorizationURL(
        redirectURI: "http://127.0.0.1:8000/oauth/callback",
        pkce: pkce,
        state: "state-1"
    )
    let query = queryItems(of: url)
    #expect(url.host == "accounts.google.com")
    #expect(query["client_id"] == "client-123")
    #expect(query["response_type"] == "code")
    #expect(query["code_challenge"] == pkce.codeChallenge)
    #expect(query["code_challenge_method"] == "S256")
    #expect(query["access_type"] == "offline")
    #expect(query["prompt"] == "consent")
    #expect(query["state"] == "state-1")
    #expect(query["scope"]?.contains("gmail.modify") == true)
    #expect(query["scope"]?.contains("gmail.settings.basic") == true)
}

@Test func redirectSchemeIsReversedClientID() {
    #expect(
        GoogleOAuthClient.redirectScheme(forClientID: "123-abc.apps.googleusercontent.com")
            == "com.googleusercontent.apps.123-abc"
    )
    #expect(GoogleOAuthClient.redirectScheme(forClientID: "invalid-client-id") == nil)
    #expect(GoogleOAuthClient.redirectScheme(forClientID: ".apps.googleusercontent.com") == nil)
}

@Test func exchangeCodeSendsFormParametersAndDecodesResponse() async throws {
    let responseJSON = """
        {
          "access_token": "at-1",
          "expires_in": 3599,
          "refresh_token": "rt-1",
          "scope": "https://www.googleapis.com/auth/gmail.modify",
          "token_type": "Bearer"
        }
        """
    let transport = MockTransport { request in
        (Data(responseJSON.utf8), httpResponse(url: request.url!, statusCode: 200))
    }
    let client = GoogleOAuthClient(configuration: configuration, transport: transport)
    let pkce = PKCE()
    let response = try await client.exchangeCode("code-1", pkce: pkce, redirectURI: "http://127.0.0.1:8000/oauth/callback")

    #expect(response.accessToken == "at-1")
    #expect(response.refreshToken == "rt-1")
    let body = transport.requests[0].formBody
    #expect(body["grant_type"] == "authorization_code")
    #expect(body["code"] == "code-1")
    #expect(body["code_verifier"] == pkce.codeVerifier)
    #expect(body["client_id"] == "client-123")
    #expect(body["client_secret"] == "secret-abc")
    #expect(body["redirect_uri"] == "http://127.0.0.1:8000/oauth/callback")
}

@Test func refreshAccessTokenSendsRefreshGrant() async throws {
    let responseJSON = """
        {"access_token": "at-2", "expires_in": 3599, "token_type": "Bearer"}
        """
    let transport = MockTransport { request in
        (Data(responseJSON.utf8), httpResponse(url: request.url!, statusCode: 200))
    }
    let client = GoogleOAuthClient(configuration: configuration, transport: transport)
    let response = try await client.refreshAccessToken(refreshToken: "rt-1")

    #expect(response.accessToken == "at-2")
    #expect(response.refreshToken == nil)
    let body = transport.requests[0].formBody
    #expect(body["grant_type"] == "refresh_token")
    #expect(body["refresh_token"] == "rt-1")
}

@Test func tokenEndpointErrorIsSurfaced() async throws {
    let transport = MockTransport { request in
        (
            Data(#"{"error": "invalid_grant", "error_description": "Token has been expired or revoked."}"#.utf8),
            httpResponse(url: request.url!, statusCode: 400)
        )
    }
    let client = GoogleOAuthClient(configuration: configuration, transport: transport)
    await #expect(throws: OAuthError.tokenEndpointFailed(
        statusCode: 400,
        error: "invalid_grant",
        description: "Token has been expired or revoked."
    )) {
        _ = try await client.refreshAccessToken(refreshToken: "rt-expired")
    }
}
