import Foundation

@testable import MailerCore

/// テスト用の最小の質問定義 (castle の review-triage.json と同じ形で、flag を 2 つに絞ったもの)。
let inquiryTestRules = InquiryRuleDefinition(
    threshold: 0.5,
    attentionFlags: ["unusable_now"],
    category: InquiryRuleDefinition.Question(
        instructions: "Which category does `review` belong to?",
        criteria: ["bug": "The app does not work", "billing": "The text is about money", "praise": "The app is good"]
    ),
    flags: [
        "unusable_now": InquiryRuleDefinition.Question(
            instructions: "Does `review` say the app is unusable right now?",
            criteria: ["true": "It crashes", "false": "It still works"]
        ),
        "refund_request": InquiryRuleDefinition.Question(
            instructions: "Does `review` ask for money back?",
            criteria: ["true": "Asks for a refund", "false": "Does not ask for money back"]
        ),
    ],
    severity: InquiryRuleDefinition.Severity(
        instructions: "How urgent is it for the developer to act on `review`?",
        levels: ["none", "low", "medium", "high"]
    )
)

/// 2026-09-22 に実 API (jev-1.13.0) が「起動しない・返金してください」の本文に返した応答の形。
let inquiryTestResponseJSON = """
    {"model":"jev-1.13.0","answers":{
      "category":{"type":"choice","choice":"bug","confidence":0.92,"probabilities":{"bug":0.94,"billing":0.06}},
      "unusable_now":{"type":"noul","noul":0.98},
      "refund_request":{"type":"noul","noul":0.99},
      "severity":{"type":"score","score":2.99,"confidence":0.99,"legend":{"0":"none","1":"low","2":"medium","3":"high"},
        "probabilities":{"0":0.0,"1":0.0,"2":0.01,"3":0.99}}
    },"usage":{"input_tokens":1034,"output_tokens":177}}
    """

/// 引数の既定値は inquiryTestResponseJSON (実 API の応答) を InquiryClassifier.parse に通した値。
func makeInquiryClassification(
    category: String = "bug",
    categoryConfidence: Double = 0.92,
    severity: String = "high",
    severityScore: Double = 2.99,
    severityConfidence: Double = 0.99,
    flags: [String: Double] = ["unusable_now": 0.98, "refund_request": 0.99]
) -> InquiryClassification {
    InquiryClassification(
        category: category,
        categoryConfidence: categoryConfidence,
        severity: severity,
        severityScore: severityScore,
        severityConfidence: severityConfidence,
        flags: flags,
        model: "jev-1.13.0",
        classifiedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
}

func makeInquiryTestStore() -> InquiryClassificationStore {
    InquiryClassificationStore(
        directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("mailer-tests-\(UUID().uuidString)", isDirectory: true)
    )
}

/// Jev API 宛てのリクエストにだけ handler で応答し、それ以外 (Gmail・OAuth) は makeGmailTestClient と同じ応答を返す transport。
func makeInquiryTestTransport(
    gmailResponses: [(statusCode: Int, body: String)] = [],
    jev handler: @escaping @Sendable (URLRequest) throws -> (Data, HTTPURLResponse)
) -> MockTransport {
    let queue = ResponseQueue(gmailResponses)
    return MockTransport { request in
        if request.url?.host == "api.typesafe.ai" {
            return try handler(request)
        }
        if request.url?.host == "oauth2.googleapis.com" {
            return (Data(gmailTestRefreshResponseJSON.utf8), httpResponse(url: request.url!, statusCode: 200))
        }
        return try queue.next(for: request.url!)
    }
}

/// makeGmailTestClient と同じ認証状態で、任意の transport を使う GmailClient。
func makeGmailClient(transport: MockTransport) -> GmailClient {
    let store = InMemoryTokenStore()
    store.save(
        StoredToken(accessToken: "at-valid", refreshToken: "rt", expiresAt: Date().addingTimeInterval(3600)),
        for: "a@example.com"
    )
    return GmailClient(
        email: "a@example.com",
        tokenProvider: TokenProvider(
            oauth: GoogleOAuthClient(configuration: OAuthConfiguration(clientID: "c"), transport: transport),
            tokenStore: store
        ),
        transport: transport,
        retryDelays: [0, 0, 0]
    )
}

/// transport が受けたリクエストのうち Jev API 宛てのものだけを返す。
func jevTestRequests(transport: MockTransport) -> [URLRequest] {
    transport.requests.filter { $0.url?.host == "api.typesafe.ai" }
}
