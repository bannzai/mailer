import Foundation
import Testing

@testable import MailerCore

private func makeClassifier(transport: MockTransport, rules: InquiryRuleDefinition = inquiryTestRules)
    -> InquiryClassifier
{
    InquiryClassifier(apiKey: "test-key", rules: rules, transport: transport, retryDelays: [0, 0], timeout: 1)
}

private func jsonObject(_ data: Data) throws -> NSDictionary {
    try #require(JSONSerialization.jsonObject(with: data) as? NSDictionary)
}

@Test func ruleDefinitionDecodesCastleJSONKeys() throws {
    let json = """
        {"_schema": "説明", "threshold": 0.5, "attention_flags": ["unusable_now"],
         "category": {"instructions": "Which?", "criteria": {"bug": "broken"}},
         "flags": {"unusable_now": {"instructions": "Unusable?", "criteria": {"true": "yes", "false": "no"}}},
         "severity": {"instructions": "How urgent?", "levels": ["none", "high"]}}
        """
    let rules = try JSONDecoder().decode(InquiryRuleDefinition.self, from: Data(json.utf8))
    #expect(rules.threshold == 0.5)
    #expect(rules.attentionFlags == ["unusable_now"])
    #expect(rules.category.criteria == ["bug": "broken"])
    #expect(rules.flags["unusable_now"]?.instructions == "Unusable?")
    #expect(rules.severity.levels == ["none", "high"])
}

@Test func requestBodyMatchesCastleClassifyReviewShape() throws {
    let body = try makeClassifier(transport: MockTransport { _ in throw URLError(.cancelled) })
        .requestBody(text: "件名: 起動しない\nアプリが落ちます")
    let expected: NSDictionary = [
        "model": "jev-1.13.0",
        "state": ["review": "件名: 起動しない\nアプリが落ちます"],
        "questions": [
            "category": [
                "type": "choice",
                "instructions": inquiryTestRules.category.instructions,
                "criteria": inquiryTestRules.category.criteria,
            ],
            "unusable_now": [
                "type": "noul",
                "instructions": inquiryTestRules.flags["unusable_now"]!.instructions,
                "criteria": inquiryTestRules.flags["unusable_now"]!.criteria,
            ],
            "refund_request": [
                "type": "noul",
                "instructions": inquiryTestRules.flags["refund_request"]!.instructions,
                "criteria": inquiryTestRules.flags["refund_request"]!.criteria,
            ],
            "severity": [
                "type": "score",
                "instructions": inquiryTestRules.severity.instructions,
                "criteria": ["none", "low", "medium", "high"],
            ],
        ],
    ]
    #expect(try jsonObject(body) == expected)
}

/// castle の classify-review.sh --dry-run の出力 (環境変数 MAILER_JEV_DRY_RUN_FIXTURE のファイル) と、
/// 同じ本文・castle の質問定義で組み立てたリクエストが一致することを確認する。CI には castle が無いため手元でだけ動く。
@Test(
    .enabled(
        if: ProcessInfo.processInfo.environment["MAILER_JEV_DRY_RUN_FIXTURE"] != nil
            && FileManager.default.fileExists(atPath: InquiryRuleDefinition.defaultFileURL.path)
    )
)
func requestBodyEqualsCastleDryRunOutput() throws {
    let fixtureURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["MAILER_JEV_DRY_RUN_FIXTURE"]!)
    let fixture = try jsonObject(Data(contentsOf: fixtureURL))
    let text = try #require((fixture["state"] as? NSDictionary)?["review"] as? String)
    let rules = try #require(try InquiryRuleDefinition.load())
    let body = try makeClassifier(transport: MockTransport { _ in throw URLError(.cancelled) }, rules: rules)
        .requestBody(text: text)
    #expect(try jsonObject(body) == fixture)
}

@Test func classifySendsBearerTokenAndParsesRealResponseShape() async throws {
    let transport = MockTransport { request in
        (Data(inquiryTestResponseJSON.utf8), httpResponse(url: request.url!, statusCode: 200))
    }
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let classification = try await makeClassifier(transport: transport).classify(text: "起動しない", now: now)

    #expect(classification == makeInquiryClassification())
    #expect(classification.adoptedFlags == ["refund_request", "unusable_now"])
    let request = try #require(transport.requests.first)
    #expect(request.url == InquiryClassifier.endpoint)
    #expect(request.httpMethod == "POST")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
    #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    #expect(request.timeoutInterval == 1)
}

@Test func classifyRejectsResponseMissingAnswer() async throws {
    let transport = MockTransport { request in
        (
            Data(
                #"{"model":"jev-1.13.0","answers":{"category":{"type":"choice","choice":"bug","confidence":0.9}}}"#.utf8
            ),
            httpResponse(url: request.url!, statusCode: 200)
        )
    }
    await #expect(throws: InquiryClassifierError.missingAnswer("severity")) {
        try await makeClassifier(transport: transport).classify(text: "x")
    }
}

@Test func classifyRejectsSeverityOutOfRange() async throws {
    let transport = MockTransport { request in
        (
            Data(
                #"{"model":"m","answers":{"category":{"type":"choice","choice":"bug","confidence":0.9},"unusable_now":{"type":"noul","noul":0.1},"refund_request":{"type":"noul","noul":0.1},"severity":{"type":"score","score":7,"confidence":0.9}}}"#
                    .utf8
            ),
            httpResponse(url: request.url!, statusCode: 200)
        )
    }
    await #expect(throws: InquiryClassifierError.severityOutOfRange(7)) {
        try await makeClassifier(transport: transport).classify(text: "x")
    }
}

@Test func classifyRetriesRateLimitThenSucceeds() async throws {
    let queue = ResponseQueue([(429, "{}"), (529, "{}"), (200, inquiryTestResponseJSON)])
    let transport = MockTransport { request in try queue.next(for: request.url!) }
    let classification = try await makeClassifier(transport: transport).classify(text: "x")
    #expect(classification.category == "bug")
    #expect(transport.requests.count == 3)
}

@Test func classifyGivesUpAfterRetryLimit() async throws {
    let transport = MockTransport { request in (Data(), httpResponse(url: request.url!, statusCode: 429)) }
    await #expect(throws: InquiryClassifierError.httpStatus(429)) {
        try await makeClassifier(transport: transport).classify(text: "x")
    }
    #expect(transport.requests.count == 3)
}

@Test func classifyDoesNotRetryOtherHTTPErrors() async throws {
    let transport = MockTransport { request in (Data(), httpResponse(url: request.url!, statusCode: 500)) }
    await #expect(throws: InquiryClassifierError.httpStatus(500)) {
        try await makeClassifier(transport: transport).classify(text: "x")
    }
    #expect(transport.requests.count == 1)
}

@Test func classifyRetriesTimeoutOnce() async throws {
    let transport = MockTransport { _ in throw URLError(.timedOut) }
    await #expect(throws: URLError.self) {
        try await makeClassifier(transport: transport).classify(text: "x")
    }
    #expect(transport.requests.count == 2)
}

@Test func bandSplitsProbabilityIntoThreeRanges() {
    #expect(InquiryClassificationBand(probability: 0.7) == .adopted)
    #expect(InquiryClassificationBand(probability: 0.99) == .adopted)
    #expect(InquiryClassificationBand(probability: 0.69) == .uncertain)
    #expect(InquiryClassificationBand(probability: 0.31) == .uncertain)
    #expect(InquiryClassificationBand(probability: 0.3) == .rejected)
    #expect(InquiryClassificationBand(probability: 0) == .rejected)
}

@Test func configurationPrefersEnvironmentThenFile() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mailer-tests-\(UUID().uuidString)", isDirectory: true)
    let environmentKey = ProcessInfo.processInfo.environment["TYPESAFE_API_KEY"]
    if let environmentKey, !environmentKey.isEmpty {
        #expect(try InquiryClassifierConfiguration.load(configDirectory: directory)?.apiKey == environmentKey)
        return
    }
    #expect(try InquiryClassifierConfiguration.load(configDirectory: directory) == nil)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data(#"{"apiKey": "from-file"}"#.utf8).write(to: directory.appendingPathComponent("typesafe.json"))
    #expect(try InquiryClassifierConfiguration.load(configDirectory: directory)?.apiKey == "from-file")
}
