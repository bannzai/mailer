import Foundation

@testable import MailerCore

let gmailTestRefreshResponseJSON = """
    {"access_token": "at-refreshed", "expires_in": 3599, "token_type": "Bearer"}
    """

/// Gmail API 呼び出しを ResponseQueue で応答する GmailClient を組み立てる。
/// OAuth のリフレッシュ要求 (oauth2.googleapis.com) には常に成功レスポンスを返す。
func makeGmailTestClient(
    gmailResponses: [(statusCode: Int, body: String)]
) -> (client: GmailClient, transport: MockTransport) {
    let queue = ResponseQueue(gmailResponses)
    let transport = MockTransport { request in
        if request.url?.host == "oauth2.googleapis.com" {
            return (Data(gmailTestRefreshResponseJSON.utf8), httpResponse(url: request.url!, statusCode: 200))
        }
        return try queue.next(for: request.url!)
    }
    let store = InMemoryTokenStore()
    store.save(
        StoredToken(accessToken: "at-valid", refreshToken: "rt", expiresAt: Date().addingTimeInterval(3600)),
        for: "a@example.com"
    )
    let client = GmailClient(
        email: "a@example.com",
        tokenProvider: TokenProvider(
            oauth: GoogleOAuthClient(configuration: OAuthConfiguration(clientID: "c"), transport: transport),
            tokenStore: store
        ),
        transport: transport,
        retryDelays: [0, 0, 0]
    )
    return (client, transport)
}

/// transport が受けたリクエストのうち Gmail API 宛てのものだけを返す。
func gmailTestRequests(_ transport: MockTransport) -> [URLRequest] {
    transport.requests.filter { $0.url?.host == "gmail.googleapis.com" }
}
