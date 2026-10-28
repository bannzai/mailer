import Foundation
import Testing

@testable import MailerCore

private func metadataMessage(id: String, from: String = "user@example.com", subject: String = "問い合わせ") -> GmailMessage {
    GmailMessage(
        id: id,
        threadId: nil,
        labelIds: ["INBOX"],
        snippet: nil,
        historyId: nil,
        internalDate: nil,
        payload: GmailMessagePart(
            partId: nil,
            mimeType: nil,
            filename: nil,
            headers: [GmailHeader(name: "From", value: from), GmailHeader(name: "Subject", value: subject)],
            body: nil,
            parts: nil
        ),
        sizeEstimate: nil
    )
}

/// format=full の取得に返す本文付きメッセージ JSON。
private func fullMessageJSON(id: String) -> String {
    #"{"id": "\#(id)", "snippet": "落ちます", "payload": {"mimeType": "text/plain", "headers": [{"name": "Subject", "value": "起動しない"}], "body": {"data": "6JC944Gh44G-44GZ"}}}"#
}

private let jevSuccess: @Sendable (URLRequest) throws -> (Data, HTTPURLResponse) = { request in
    (Data(inquiryTestResponseJSON.utf8), httpResponse(url: request.url!, statusCode: 200))
}

private func makePipeline(
    transport: MockTransport,
    store: InquiryClassificationStore,
    classifierAvailable: Bool = true
) -> InquiryClassificationPipeline {
    let gmail = makeGmailClient(transport: transport)
    return InquiryClassificationPipeline(
        gmail: gmail,
        classifier: classifierAvailable
            ? InquiryClassifier(
                apiKey: "k", rules: inquiryTestRules, transport: transport, retryDelays: [0], timeout: 1)
            : nil,
        store: store
    )
}

@Test func pipelineClassifiesUnstoredMessagesAndSaves() async throws {
    let store = makeInquiryTestStore()
    let transport = makeInquiryTestTransport(gmailResponses: [(200, fullMessageJSON(id: "m1"))], jev: jevSuccess)
    let run = await makePipeline(transport: transport, store: store).classify(messages: [metadataMessage(id: "m1")])

    #expect(run.classifiedMessageIds == ["m1"])
    #expect(run.unavailableMessageIds.isEmpty)
    #expect(run.unavailableReason == nil)
    #expect(run.classifications["m1"]?.category == "bug")
    #expect(try store.load(account: "a@example.com")["m1"]?.category == "bug")

    let gmailRequests = gmailTestRequests(transport)
    #expect(gmailRequests.count == 1)
    #expect(gmailRequests[0].url?.query?.contains("format=full") == true)
    let jevBody = try #require(jevTestRequests(transport: transport).first?.httpBody)
    let sent = try #require(JSONSerialization.jsonObject(with: jevBody) as? NSDictionary)
    #expect((sent["state"] as? NSDictionary)?["review"] as? String == "件名: 起動しない\n\n落ちます")
}

@Test func pipelineSkipsAPIForStoredMessages() async throws {
    let store = makeInquiryTestStore()
    try store.save(["m1": makeInquiryClassification(category: "praise")], account: "a@example.com")
    let transport = makeInquiryTestTransport(jev: jevSuccess)
    let run = await makePipeline(transport: transport, store: store).classify(messages: [metadataMessage(id: "m1")])

    #expect(run.classifications["m1"]?.category == "praise")
    #expect(run.classifiedMessageIds.isEmpty)
    #expect(transport.requests.isEmpty)
}

@Test func pipelineTreatsAPIErrorAsUnavailableWithoutThrowing() async throws {
    let store = makeInquiryTestStore()
    let transport = makeInquiryTestTransport(
        gmailResponses: [(200, fullMessageJSON(id: "m1")), (200, fullMessageJSON(id: "m2"))],
        jev: { request in (Data(), httpResponse(url: request.url!, statusCode: 500)) }
    )
    let run = await makePipeline(transport: transport, store: store)
        .classify(messages: [metadataMessage(id: "m1"), metadataMessage(id: "m2")])

    #expect(run.classifications.isEmpty)
    #expect(run.unavailableMessageIds == ["m1", "m2"])
    #expect(run.unavailableReason == InquiryClassifierError.httpStatus(500).localizedDescription)
    #expect(try store.load(account: "a@example.com").isEmpty)
    // 1 度失敗したら残りは API を呼ばない (不達時にメール件数分は待たない)
    #expect(jevTestRequests(transport: transport).count == 1)
    #expect(gmailTestRequests(transport).count == 1)
}

/// 本文を復号できないメールはそのメールだけ判定なしにし、残りのメールは判定を続ける。
@Test func pipelineSkipsUndecodableBodyAndContinues() async throws {
    let store = makeInquiryTestStore()
    let undecodable =
        #"{"id": "m1", "payload": {"mimeType": "text/plain", "headers": [{"name": "Content-Type", "value": "text/plain; charset=\"x-nope\""}], "body": {"data": "eA"}}}"#
    let transport = makeInquiryTestTransport(
        gmailResponses: [(200, undecodable), (200, fullMessageJSON(id: "m2"))],
        jev: jevSuccess
    )
    let run = await makePipeline(transport: transport, store: store)
        .classify(messages: [metadataMessage(id: "m1"), metadataMessage(id: "m2")])

    #expect(run.unavailableMessageIds == ["m1"])
    #expect(run.unavailableReason == GmailMessageBodyError.undecodableBody(charset: "x-nope").localizedDescription)
    #expect(run.classifiedMessageIds == ["m2"])
    #expect(try store.load(account: "a@example.com").keys.sorted() == ["m2"])
    #expect(jevTestRequests(transport: transport).count == 1)
}

@Test func pipelineTreatsTimeoutAsUnavailable() async throws {
    let store = makeInquiryTestStore()
    let transport = makeInquiryTestTransport(
        gmailResponses: [(200, fullMessageJSON(id: "m1"))],
        jev: { _ in throw URLError(.timedOut) }
    )
    let run = await makePipeline(transport: transport, store: store).classify(messages: [metadataMessage(id: "m1")])

    #expect(run.unavailableMessageIds == ["m1"])
    #expect(run.unavailableReason == URLError(.timedOut).localizedDescription)
    #expect(try store.load(account: "a@example.com").isEmpty)
}

@Test func pipelineWithoutClassifierMarksAllUnavailable() async throws {
    let transport = makeInquiryTestTransport(jev: jevSuccess)
    let run = await makePipeline(transport: transport, store: makeInquiryTestStore(), classifierAvailable: false)
        .classify(messages: [metadataMessage(id: "m1")])

    #expect(run.unavailableMessageIds == ["m1"])
    #expect(run.unavailableReason?.contains("TYPESAFE_API_KEY") == true)
    #expect(transport.requests.isEmpty)
}

/// issue #28 の完了条件: API 不達時に受信処理が止まらず、既存の通知経路 (分類を使わない枠と defaultPolicy) に流れる。
@Test func unavailableClassificationFallsThroughToExistingNotificationRoute() async throws {
    let transport = makeInquiryTestTransport(
        gmailResponses: [(200, fullMessageJSON(id: "m1"))],
        jev: { _ in throw URLError(.cannotConnectToHost) }
    )
    let message = metadataMessage(id: "m1", from: "user@example.com")
    let run = await makePipeline(transport: transport, store: makeInquiryTestStore()).classify(messages: [message])
    let rules = [
        NotificationRule(
            name: "緊急",
            condition: NotificationRuleCondition(
                classification: InquiryClassificationCondition(flags: ["unusable_now"], severities: ["high"])
            ),
            policy: .immediate
        ),
        NotificationRule(
            name: "問い合わせまとめ",
            condition: NotificationRuleCondition(fromDomain: "example.com"),
            policy: .batch(interval: 43200)
        ),
    ]
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let decision = NotificationEngine.decide(
        messages: [message],
        rules: rules,
        states: [:],
        now: now,
        classifications: run.classifications
    )
    #expect(decision.deliveries == [NotificationDelivery(ruleName: "問い合わせまとめ", messageIds: ["m1"])])
    #expect(decision.states["緊急"] == nil)
}
