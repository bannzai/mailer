import Foundation
import Testing

@testable import MailerCore

private let refreshResponseJSON = """
    {"access_token": "at-refreshed", "expires_in": 3599, "token_type": "Bearer"}
    """

private func makeClient(
    gmailResponses: [(statusCode: Int, body: String)]
) -> (client: GmailClient, transport: MockTransport) {
    let queue = ResponseQueue(gmailResponses)
    let transport = MockTransport { request in
        if request.url?.host == "oauth2.googleapis.com" {
            return (Data(refreshResponseJSON.utf8), httpResponse(url: request.url!, statusCode: 200))
        }
        return try queue.next(for: request.url!)
    }
    let store = InMemoryTokenStore()
    store.save(
        StoredToken(accessToken: "at-valid", refreshToken: "rt", expiresAt: Date().addingTimeInterval(3600)),
        for: "a@example.com"
    )
    let provider = TokenProvider(
        oauth: GoogleOAuthClient(configuration: OAuthConfiguration(clientID: "c"), transport: transport),
        tokenStore: store
    )
    let client = GmailClient(
        email: "a@example.com",
        tokenProvider: provider,
        transport: transport,
        retryDelays: [0, 0, 0]
    )
    return (client, transport)
}

private func gmailRequests(_ transport: MockTransport) -> [URLRequest] {
    transport.requests.filter { $0.url?.host == "gmail.googleapis.com" }
}

@Test func getMessageDecodesFullPayload() async throws {
    let messageJSON = """
        {
          "id": "m-1",
          "threadId": "t-1",
          "labelIds": ["INBOX", "UNREAD"],
          "snippet": "こんにちは",
          "internalDate": "1721900000000",
          "payload": {
            "mimeType": "multipart/alternative",
            "headers": [
              {"name": "From", "value": "Sender <sender@example.com>"},
              {"name": "Subject", "value": "件名テスト"}
            ],
            "parts": [
              {"partId": "0", "mimeType": "text/plain", "body": {"size": 5, "data": "SGVsbG8"}},
              {"partId": "1", "mimeType": "text/html", "body": {"size": 14, "data": "PGgxPkhlbGxvPC9oMT4"}}
            ]
          }
        }
        """
    let (client, transport) = makeClient(gmailResponses: [(200, messageJSON)])
    let message = try await client.getMessage(id: "m-1")

    #expect(message.from == "Sender <sender@example.com>")
    #expect(message.subject == "件名テスト")
    #expect(message.labelIds == ["INBOX", "UNREAD"])
    #expect(message.date == Date(timeIntervalSince1970: 1_721_900_000))
    let html = message.payload?.firstPart(mimeType: "text/html")
    #expect(html.flatMap { $0.body?.decodedData }.map { String(decoding: $0, as: UTF8.self) } == "<h1>Hello</h1>")
    #expect(gmailRequests(transport).first?.url?.query()?.contains("format=full") == true)
}

@Test func listMessagesBuildsQueryParameters() async throws {
    let (client, transport) = makeClient(gmailResponses: [
        (200, #"{"messages": [{"id": "m-1", "threadId": "t-1"}], "resultSizeEstimate": 1}"#)
    ])
    let list = try await client.listMessages(query: "from:news@example.com", labelIds: ["INBOX"], maxResults: 50)

    #expect(list.messages?.map(\.id) == ["m-1"])
    let url = try #require(gmailRequests(transport).first?.url)
    let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
    #expect(query.contains(URLQueryItem(name: "q", value: "from:news@example.com")))
    #expect(query.contains(URLQueryItem(name: "labelIds", value: "INBOX")))
    #expect(query.contains(URLQueryItem(name: "maxResults", value: "50")))
}

@Test func listAllMessagesFollowsNextPageToken() async throws {
    let (client, transport) = makeClient(gmailResponses: [
        (200, #"{"messages": [{"id": "m-1", "threadId": "t-1"}], "nextPageToken": "page-2"}"#),
        (200, #"{"messages": [{"id": "m-2", "threadId": "t-2"}]}"#),
    ])
    let refs = try await client.listAllMessages(query: "in:inbox")

    #expect(refs.map(\.id) == ["m-1", "m-2"])
    let requests = gmailRequests(transport)
    #expect(requests.count == 2)
    #expect(requests[1].url?.query()?.contains("pageToken=page-2") == true)
}

@Test func unauthorizedResponseTriggersRefreshAndRetry() async throws {
    let (client, transport) = makeClient(gmailResponses: [
        (401, #"{"error": {"code": 401, "message": "Invalid Credentials", "status": "UNAUTHENTICATED"}}"#),
        (200, #"{"emailAddress": "a@example.com", "messagesTotal": 1, "threadsTotal": 1, "historyId": "100"}"#),
    ])
    let profile = try await client.getProfile()

    #expect(profile.emailAddress == "a@example.com")
    let requests = gmailRequests(transport)
    #expect(requests.count == 2)
    #expect(requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer at-valid")
    #expect(requests[1].value(forHTTPHeaderField: "Authorization") == "Bearer at-refreshed")
}

@Test func rateLimitAndServerErrorsAreRetriedWithBackoff() async throws {
    let (client, transport) = makeClient(gmailResponses: [
        (429, #"{"error": {"code": 429, "message": "Rate limited", "status": "RESOURCE_EXHAUSTED"}}"#),
        (503, #"{"error": {"code": 503, "message": "Backend error", "status": "UNAVAILABLE"}}"#),
        (200, #"{"labels": [{"id": "Label_1", "name": "newsletter"}]}"#),
    ])
    let labels = try await client.listLabels()

    #expect(labels.map(\.name) == ["newsletter"])
    #expect(gmailRequests(transport).count == 3)
}

@Test func retryGivesUpAfterConfiguredAttempts() async throws {
    let rateLimited = #"{"error": {"code": 429, "message": "Rate limited", "status": "RESOURCE_EXHAUSTED"}}"#
    let (client, transport) = makeClient(gmailResponses: [
        (429, rateLimited), (429, rateLimited), (429, rateLimited), (429, rateLimited),
    ])
    await #expect(throws: GmailAPIError(statusCode: 429, message: "Rate limited", status: "RESOURCE_EXHAUSTED")) {
        _ = try await client.listLabels()
    }
    #expect(gmailRequests(transport).count == 4)
}

@Test func batchModifySplitsIntoChunksOf1000() async throws {
    let ids = (0..<2500).map { "m-\($0)" }
    let (client, transport) = makeClient(gmailResponses: [(204, ""), (204, ""), (204, "")])
    try await client.batchModify(ids: ids, addLabelIds: ["Label_1"], removeLabelIds: ["INBOX"])

    let requests = gmailRequests(transport)
    #expect(requests.count == 3)
    let decoded = try requests.map { try JSONDecoder().decode(BatchModifyRequest.self, from: $0.httpBody ?? Data()) }
    #expect(decoded.map(\.ids.count) == [1000, 1000, 500])
    #expect(decoded.allSatisfy { $0.addLabelIds == ["Label_1"] && $0.removeLabelIds == ["INBOX"] })
    #expect(decoded.flatMap(\.ids) == ids)
}

@Test func apiErrorBodyIsDecoded() async throws {
    let (client, _) = makeClient(gmailResponses: [
        (404, #"{"error": {"code": 404, "message": "Requested entity was not found.", "status": "NOT_FOUND"}}"#)
    ])
    await #expect(throws: GmailAPIError(statusCode: 404, message: "Requested entity was not found.", status: "NOT_FOUND")) {
        _ = try await client.getMessage(id: "missing")
    }
}

@Test func historyListDecodesAndSendsStartHistoryId() async throws {
    let historyJSON = """
        {
          "history": [
            {"id": "200", "messagesAdded": [{"message": {"id": "m-9", "threadId": "t-9"}, "labelIds": ["INBOX"]}]}
          ],
          "historyId": "201"
        }
        """
    let (client, transport) = makeClient(gmailResponses: [(200, historyJSON)])
    let history = try await client.listHistory(startHistoryId: "100", historyTypes: ["messageAdded"])

    #expect(history.history?.first?.messagesAdded?.first?.message?.id == "m-9")
    let url = try #require(gmailRequests(transport).first?.url)
    #expect(url.query()?.contains("startHistoryId=100") == true)
    #expect(url.query()?.contains("historyTypes=messageAdded") == true)
}
