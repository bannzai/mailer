import Foundation
import Testing

@testable import MailerCore

private func makeMessage(
    id: String,
    from: String? = nil,
    subject: String? = nil,
    labelIds: [String]? = nil
) -> GmailMessage {
    GmailMessage(
        id: id,
        threadId: nil,
        labelIds: labelIds,
        snippet: nil,
        historyId: nil,
        internalDate: nil,
        payload: GmailMessagePart(
            partId: nil,
            mimeType: nil,
            filename: nil,
            headers: [
                from.map { GmailHeader(name: "From", value: $0) },
                subject.map { GmailHeader(name: "Subject", value: $0) },
            ].compactMap(\.self),
            body: nil,
            parts: nil
        ),
        sizeEstimate: nil
    )
}

@Test func conditionMatchesFromAddressIgnoringCase() {
    let condition = NotificationRuleCondition(fromAddress: "news@example.com")
    #expect(condition.matches(message: makeMessage(id: "m1", from: "News <NEWS@Example.com>")))
    #expect(!condition.matches(message: makeMessage(id: "m2", from: "Other <other@example.com>")))
    #expect(!condition.matches(message: makeMessage(id: "m3")))
}

@Test func conditionMatchesFromDomain() {
    let condition = NotificationRuleCondition(fromDomain: "example.com")
    #expect(condition.matches(message: makeMessage(id: "m1", from: "News <news@EXAMPLE.com>")))
    #expect(!condition.matches(message: makeMessage(id: "m2", from: "news@other.com")))
    #expect(!condition.matches(message: makeMessage(id: "m3", from: "壊れたヘッダ")))
}

@Test func conditionMatchesSubjectContains() {
    let condition = NotificationRuleCondition(subjectContains: "invoice")
    #expect(condition.matches(message: makeMessage(id: "m1", subject: "Your INVOICE is ready")))
    #expect(!condition.matches(message: makeMessage(id: "m2", subject: "領収書")))
    #expect(!condition.matches(message: makeMessage(id: "m3")))
}

@Test func conditionRequiresAllLabelIds() {
    let condition = NotificationRuleCondition(labelIds: ["INBOX", "IMPORTANT"])
    #expect(condition.matches(message: makeMessage(id: "m1", labelIds: ["INBOX", "IMPORTANT", "UNREAD"])))
    #expect(!condition.matches(message: makeMessage(id: "m2", labelIds: ["INBOX"])))
    #expect(!condition.matches(message: makeMessage(id: "m3")))
}

@Test func conditionCombinesFieldsWithAnd() {
    let condition = NotificationRuleCondition(
        fromDomain: "example.com",
        subjectContains: "請求",
        labelIds: ["INBOX"]
    )
    #expect(
        condition.matches(
            message: makeMessage(id: "m1", from: "news@example.com", subject: "今月の請求書", labelIds: ["INBOX"])
        )
    )
    #expect(
        !condition.matches(
            message: makeMessage(id: "m2", from: "news@other.com", subject: "今月の請求書", labelIds: ["INBOX"])
        )
    )
    #expect(
        !condition.matches(
            message: makeMessage(id: "m3", from: "news@example.com", subject: "お知らせ", labelIds: ["INBOX"])
        )
    )
    #expect(
        !condition.matches(
            message: makeMessage(id: "m4", from: "news@example.com", subject: "今月の請求書", labelIds: ["SPAM"])
        )
    )
}

@Test func emptyConditionMatchesEveryMessage() {
    #expect(NotificationRuleCondition().matches(message: makeMessage(id: "m1")))
    #expect(NotificationRuleCondition().matches(message: makeMessage(id: "m2", from: "news@example.com")))
}

@Test func firstMatchingPrefersEarlierRule() {
    let rules = [
        NotificationRule(
            name: "ニュースレター",
            condition: NotificationRuleCondition(fromAddress: "news@example.com"),
            policy: .batch(interval: 43200)
        ),
        NotificationRule(
            name: "example ドメイン",
            condition: NotificationRuleCondition(fromDomain: "example.com"),
            policy: .immediate
        ),
    ]
    #expect(rules.firstMatching(message: makeMessage(id: "m1", from: "news@example.com"))?.name == "ニュースレター")
    #expect(rules.firstMatching(message: makeMessage(id: "m2", from: "other@example.com"))?.name == "example ドメイン")
    #expect(rules.firstMatching(message: makeMessage(id: "m3", from: "other@other.com")) == nil)
}

@Test func notificationRuleSurvivesJSONRoundTrip() throws {
    let rules = [
        NotificationRule(
            name: "即時",
            condition: NotificationRuleCondition(fromAddress: "boss@example.com"),
            policy: .immediate
        ),
        NotificationRule(
            name: "まとめ",
            condition: NotificationRuleCondition(fromDomain: "example.com", labelIds: ["INBOX"]),
            policy: .batch(interval: 43200)
        ),
        NotificationRule(
            name: "無音",
            condition: NotificationRuleCondition(subjectContains: "広告"),
            policy: .silent
        ),
    ]
    #expect(try JSONDecoder().decode([NotificationRule].self, from: JSONEncoder().encode(rules)) == rules)
}
