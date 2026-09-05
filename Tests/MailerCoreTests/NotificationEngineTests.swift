import Foundation
import Testing

@testable import MailerCore

private let now = Date(timeIntervalSince1970: 1_700_000_000)
/// バッチ枠のテストで使う間隔 (12 時間)。
private let twelveHours: TimeInterval = 43200

private func makeMessage(id: String, from: String) -> GmailMessage {
    GmailMessage(
        id: id,
        threadId: nil,
        labelIds: nil,
        snippet: nil,
        historyId: nil,
        internalDate: nil,
        payload: GmailMessagePart(
            partId: nil,
            mimeType: nil,
            filename: nil,
            headers: [GmailHeader(name: "From", value: from)],
            body: nil,
            parts: nil
        ),
        sizeEstimate: nil
    )
}

private func makeRule(name: String, domain: String, policy: NotificationPolicy) -> NotificationRule {
    NotificationRule(name: name, condition: NotificationRuleCondition(fromDomain: domain), policy: policy)
}

@Test func unmatchedMessagesAreNotifiedImmediately() {
    let decision = NotificationEngine.decide(
        messages: [makeMessage(id: "m1", from: "a@example.com"), makeMessage(id: "m2", from: "b@other.com")],
        rules: [],
        states: [:],
        now: now
    )
    #expect(decision.deliveries == [NotificationDelivery(ruleName: nil, messageIds: ["m1", "m2"])])
    #expect(decision.states.isEmpty)
    #expect(decision.immediateMessageIds == ["m1", "m2"])
    #expect(decision.deferredMessageIds.isEmpty)
}

@Test func immediateRuleNotifiesArrivedMessages() {
    let decision = NotificationEngine.decide(
        messages: [makeMessage(id: "m1", from: "boss@example.com")],
        rules: [makeRule(name: "仕事", domain: "example.com", policy: .immediate)],
        states: [:],
        now: now
    )
    #expect(decision.deliveries == [NotificationDelivery(ruleName: "仕事", messageIds: ["m1"])])
    #expect(decision.states["仕事"]?.lastNotifiedAt == now)
    #expect(decision.states["仕事"]?.pendingMessageIds.isEmpty == true)
    #expect(decision.deferredMessageIds.isEmpty)
}

@Test func immediateRuleFlushesPendingLeftByPolicyChange() {
    let decision = NotificationEngine.decide(
        messages: [],
        rules: [makeRule(name: "仕事", domain: "example.com", policy: .immediate)],
        states: ["仕事": NotificationRuleState(pendingMessageIds: ["p1"])],
        now: now
    )
    #expect(decision.deliveries == [NotificationDelivery(ruleName: "仕事", messageIds: ["p1"])])
    #expect(decision.states["仕事"]?.pendingMessageIds.isEmpty == true)
    #expect(decision.states["仕事"]?.lastNotifiedAt == now)
}

@Test func immediateRuleDeliversPendingBeforeArrivals() {
    let decision = NotificationEngine.decide(
        messages: [makeMessage(id: "m1", from: "boss@example.com")],
        rules: [makeRule(name: "仕事", domain: "example.com", policy: .immediate)],
        states: ["仕事": NotificationRuleState(pendingMessageIds: ["p1"])],
        now: now
    )
    #expect(decision.deliveries == [NotificationDelivery(ruleName: "仕事", messageIds: ["p1", "m1"])])
    #expect(decision.deferredMessageIds.isEmpty)
}

@Test func batchRuleNotifiesFirstArrivalImmediately() {
    let decision = NotificationEngine.decide(
        messages: [makeMessage(id: "m1", from: "news@example.com")],
        rules: [makeRule(name: "まとめ", domain: "example.com", policy: .batch(interval: twelveHours))],
        states: [:],
        now: now
    )
    #expect(decision.deliveries == [NotificationDelivery(ruleName: "まとめ", messageIds: ["m1"])])
    #expect(decision.states["まとめ"]?.lastNotifiedAt == now)
    #expect(decision.states["まとめ"]?.pendingMessageIds.isEmpty == true)
}

@Test func batchRuleDefersWithinInterval() {
    let decision = NotificationEngine.decide(
        messages: [makeMessage(id: "m1", from: "news@example.com")],
        rules: [makeRule(name: "まとめ", domain: "example.com", policy: .batch(interval: twelveHours))],
        states: ["まとめ": NotificationRuleState(lastNotifiedAt: now.addingTimeInterval(-3600))],
        now: now
    )
    #expect(decision.deliveries.isEmpty)
    #expect(decision.deferredMessageIds["まとめ"] == ["m1"])
    #expect(decision.states["まとめ"]?.lastNotifiedAt == now.addingTimeInterval(-3600))
}

@Test func batchRuleAccumulatesPendingWithoutDuplicates() {
    let decision = NotificationEngine.decide(
        messages: [makeMessage(id: "p1", from: "news@example.com"), makeMessage(id: "m1", from: "news@example.com")],
        rules: [makeRule(name: "まとめ", domain: "example.com", policy: .batch(interval: twelveHours))],
        states: [
            "まとめ": NotificationRuleState(lastNotifiedAt: now.addingTimeInterval(-3600), pendingMessageIds: ["p1"])
        ],
        now: now
    )
    #expect(decision.deliveries.isEmpty)
    #expect(decision.deferredMessageIds["まとめ"] == ["p1", "m1"])
}

@Test func batchRuleFlushesPendingWhenIntervalElapsed() {
    let decision = NotificationEngine.decide(
        messages: [makeMessage(id: "m1", from: "news@example.com")],
        rules: [makeRule(name: "まとめ", domain: "example.com", policy: .batch(interval: twelveHours))],
        states: [
            "まとめ": NotificationRuleState(
                lastNotifiedAt: now.addingTimeInterval(-13 * 3600),
                pendingMessageIds: ["p1"]
            )
        ],
        now: now
    )
    #expect(decision.deliveries == [NotificationDelivery(ruleName: "まとめ", messageIds: ["p1", "m1"])])
    #expect(decision.states["まとめ"]?.pendingMessageIds.isEmpty == true)
    #expect(decision.states["まとめ"]?.lastNotifiedAt == now)
}

@Test func batchRuleFlushesPendingWithoutNewMessages() {
    let decision = NotificationEngine.decide(
        messages: [],
        rules: [makeRule(name: "まとめ", domain: "example.com", policy: .batch(interval: twelveHours))],
        states: [
            "まとめ": NotificationRuleState(
                lastNotifiedAt: now.addingTimeInterval(-13 * 3600),
                pendingMessageIds: ["p1"]
            )
        ],
        now: now
    )
    #expect(decision.deliveries == [NotificationDelivery(ruleName: "まとめ", messageIds: ["p1"])])
    #expect(decision.deferredMessageIds.isEmpty)
}

@Test func silentRuleNeitherNotifiesNorDefers() {
    let decision = NotificationEngine.decide(
        messages: [makeMessage(id: "m1", from: "ad@example.com")],
        rules: [makeRule(name: "無音", domain: "example.com", policy: .silent)],
        states: [:],
        now: now
    )
    #expect(decision.deliveries.isEmpty)
    #expect(decision.immediateMessageIds.isEmpty)
    #expect(decision.deferredMessageIds.isEmpty)
    #expect(decision.states["無音"]?.pendingMessageIds ?? [] == [])
    #expect(decision.states["無音"]?.lastNotifiedAt == nil)
}

@Test func silentRuleClearsPendingLeftByPolicyChange() {
    let decision = NotificationEngine.decide(
        messages: [],
        rules: [makeRule(name: "無音", domain: "example.com", policy: .silent)],
        states: ["無音": NotificationRuleState(pendingMessageIds: ["p1"])],
        now: now
    )
    #expect(decision.deliveries.isEmpty)
    #expect(decision.deferredMessageIds.isEmpty)
    #expect(decision.states["無音"]?.pendingMessageIds == [])
}

@Test func duplicateRuleNamesKeepFirstMatchWins() {
    let decision = NotificationEngine.decide(
        messages: [makeMessage(id: "ma", from: "news@a.com"), makeMessage(id: "mb", from: "news@b.com")],
        rules: [
            makeRule(name: "重複", domain: "a.com", policy: .silent),
            makeRule(name: "重複", domain: "b.com", policy: .immediate),
        ],
        states: [:],
        now: now
    )
    #expect(decision.deliveries == [NotificationDelivery(ruleName: "重複", messageIds: ["mb"])])
    #expect(decision.immediateMessageIds == ["mb"])
    #expect(decision.deferredMessageIds.isEmpty)
}

@Test func mixedRulesOrderDeliveriesAndKeepUnknownRuleState() {
    let decision = NotificationEngine.decide(
        messages: [
            makeMessage(id: "m1", from: "news@batch.example.com"),
            makeMessage(id: "m2", from: "boss@work.example.com"),
            makeMessage(id: "m3", from: "someone@other.com"),
        ],
        rules: [
            makeRule(name: "仕事", domain: "work.example.com", policy: .immediate),
            makeRule(name: "まとめ", domain: "batch.example.com", policy: .batch(interval: twelveHours)),
        ],
        states: [
            "まとめ": NotificationRuleState(lastNotifiedAt: now.addingTimeInterval(-3600)),
            "削除済みの枠": NotificationRuleState(lastNotifiedAt: now.addingTimeInterval(-7200), pendingMessageIds: ["x1"]),
        ],
        now: now
    )
    #expect(
        decision.deliveries == [
            NotificationDelivery(ruleName: "仕事", messageIds: ["m2"]),
            NotificationDelivery(ruleName: nil, messageIds: ["m3"]),
        ]
    )
    #expect(decision.deferredMessageIds["まとめ"] == ["m1"])
    #expect(decision.states["削除済みの枠"]?.pendingMessageIds == ["x1"])
}

@Test func decideSplitsArrivalsIntoImmediateAndDeferred() {
    let decision = NotificationEngine.decide(
        messages: [
            makeMessage(id: "m1", from: "boss@work.example.com"),
            makeMessage(id: "m2", from: "news@batch.example.com"),
            makeMessage(id: "m3", from: "ad@silent.example.com"),
            makeMessage(id: "m4", from: "friend@other.com"),
        ],
        rules: [
            makeRule(name: "仕事", domain: "work.example.com", policy: .immediate),
            makeRule(name: "まとめ", domain: "batch.example.com", policy: .batch(interval: twelveHours)),
            makeRule(name: "無音", domain: "silent.example.com", policy: .silent),
        ],
        states: ["まとめ": NotificationRuleState(lastNotifiedAt: now.addingTimeInterval(-3600))],
        now: now
    )
    #expect(decision.immediateMessageIds == ["m1", "m4"])
    #expect(decision.deferredMessageIds == ["まとめ": ["m2"]])
}
