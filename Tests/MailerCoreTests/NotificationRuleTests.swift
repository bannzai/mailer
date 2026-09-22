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

@Test func classificationConditionRequiresClassification() {
    let condition = NotificationRuleCondition(
        classification: InquiryClassificationCondition(flags: ["unusable_now"])
    )
    #expect(!condition.matches(message: makeMessage(id: "m1")))
    #expect(!condition.matches(message: makeMessage(id: "m1"), classification: nil))
    #expect(condition.matches(message: makeMessage(id: "m1"), classification: makeInquiryClassification()))
}

@Test func classificationConditionMatchesOnlyAdoptedBand() {
    let flagCondition = InquiryClassificationCondition(flags: ["refund_request"])
    #expect(flagCondition.matches(classification: makeInquiryClassification(flags: ["refund_request": 0.7])))
    #expect(!flagCondition.matches(classification: makeInquiryClassification(flags: ["refund_request": 0.5])))
    #expect(!flagCondition.matches(classification: makeInquiryClassification(flags: ["refund_request": 0.1])))
    #expect(!flagCondition.matches(classification: makeInquiryClassification(flags: [:])))

    let categoryCondition = InquiryClassificationCondition(categories: ["billing", "bug"])
    #expect(
        categoryCondition.matches(classification: makeInquiryClassification(category: "bug", categoryConfidence: 0.9)))
    #expect(
        !categoryCondition.matches(classification: makeInquiryClassification(category: "bug", categoryConfidence: 0.6)))
    #expect(
        !categoryCondition.matches(
            classification: makeInquiryClassification(category: "praise", categoryConfidence: 0.9)))

    let severityCondition = InquiryClassificationCondition(severities: ["high"])
    #expect(
        severityCondition.matches(classification: makeInquiryClassification(severity: "high", severityConfidence: 0.8)))
    #expect(
        !severityCondition.matches(classification: makeInquiryClassification(severity: "high", severityConfidence: 0.4))
    )
    #expect(
        !severityCondition.matches(
            classification: makeInquiryClassification(severity: "medium", severityConfidence: 0.9)))
}

@Test func classificationConditionCombinesGroupsWithOrAndOtherFieldsWithAnd() {
    let condition = NotificationRuleCondition(
        fromDomain: "example.com",
        classification: InquiryClassificationCondition(flags: ["unusable_now", "refund_request"], severities: ["high"])
    )
    let onlySeverity = makeInquiryClassification(flags: ["unusable_now": 0.1, "refund_request": 0.1])
    #expect(condition.matches(message: makeMessage(id: "m1", from: "user@example.com"), classification: onlySeverity))
    let onlyFlag = makeInquiryClassification(severity: "low", flags: ["unusable_now": 0.1, "refund_request": 0.9])
    #expect(condition.matches(message: makeMessage(id: "m2", from: "user@example.com"), classification: onlyFlag))
    let neither = makeInquiryClassification(severity: "low", flags: ["unusable_now": 0.1, "refund_request": 0.2])
    #expect(!condition.matches(message: makeMessage(id: "m3", from: "user@example.com"), classification: neither))
    #expect(!condition.matches(message: makeMessage(id: "m4", from: "user@other.com"), classification: onlySeverity))
}

@Test func notificationRuleSurvivesJSONRoundTrip() throws {
    let rules = [
        NotificationRule(
            name: "即時",
            condition: NotificationRuleCondition(fromAddress: "boss@example.com"),
            policy: .immediate
        ),
        NotificationRule(
            name: "緊急",
            condition: NotificationRuleCondition(
                classification: InquiryClassificationCondition(
                    categories: ["billing"],
                    flags: ["unusable_now", "refund_request"],
                    severities: ["high"]
                )
            ),
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

/// PR #27 で保存した分類条件の無い枠定義 (classification キーが無い JSON) をそのまま読める。
@Test func notificationRuleDecodesJSONWithoutClassificationKey() throws {
    let json =
        #"[{"name": "まとめ", "condition": {"fromDomain": "example.com"}, "policy": {"batch": {"interval": 43200}}}]"#
    let rules = try JSONDecoder().decode([NotificationRule].self, from: Data(json.utf8))
    #expect(
        rules == [
            NotificationRule(
                name: "まとめ",
                condition: NotificationRuleCondition(fromDomain: "example.com"),
                policy: .batch(interval: 43200)
            )
        ])
}
