import Foundation
import Testing

@testable import MailerCore

private func makeTestDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("mailer-tests-\(UUID().uuidString)", isDirectory: true)
}

private func makeRule(name: String, policy: NotificationPolicy) -> NotificationRule {
    NotificationRule(
        name: name,
        condition: NotificationRuleCondition(fromDomain: "example.com"),
        policy: policy
    )
}

@Test func notificationRuleStoreLoadsEmptyWhenFileMissing() throws {
    #expect(try NotificationRuleStore(directory: makeTestDirectory()).load().isEmpty)
}

@Test func notificationRuleStoreAddReplacesRuleWithSameName() throws {
    let store = NotificationRuleStore(directory: makeTestDirectory())
    try store.add(makeRule(name: "まとめ", policy: .immediate))
    try store.add(makeRule(name: "無音", policy: .silent))
    #expect(try store.load() == [makeRule(name: "まとめ", policy: .immediate), makeRule(name: "無音", policy: .silent)])

    try store.add(makeRule(name: "まとめ", policy: .batch(interval: 43200)))
    #expect(try store.load().count == 2)
    #expect(try store.load()[0] == makeRule(name: "まとめ", policy: .batch(interval: 43200)))
}

@Test func notificationRuleStoreRemoveRejectsUnknownName() throws {
    let store = NotificationRuleStore(directory: makeTestDirectory())
    try store.add(makeRule(name: "まとめ", policy: .immediate))
    try store.remove(name: "まとめ")
    #expect(try store.load().isEmpty)
    #expect(throws: NotificationRuleStoreError.unknownRule("まとめ")) {
        try store.remove(name: "まとめ")
    }
}

@Test func notificationRuleStoreRejectsDuplicateNames() throws {
    let directory = makeTestDirectory()
    let store = NotificationRuleStore(directory: directory)
    #expect(throws: NotificationRuleStoreError.duplicateRuleName("まとめ")) {
        try store.save([makeRule(name: "まとめ", policy: .immediate), makeRule(name: "まとめ", policy: .silent)])
    }

    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try JSONEncoder().encode([makeRule(name: "まとめ", policy: .immediate), makeRule(name: "まとめ", policy: .silent)])
        .write(to: directory.appendingPathComponent("notification-rules.json"))
    #expect(throws: NotificationRuleStoreError.duplicateRuleName("まとめ")) {
        try store.load()
    }
}

@Test func notificationStateStoreKeepsOtherAccounts() throws {
    let store = NotificationStateStore(directory: makeTestDirectory())
    #expect(try store.load(account: "a@example.com").isEmpty)

    let statesOfA = [
        "まとめ": NotificationRuleState(
            lastNotifiedAt: Date(timeIntervalSince1970: 1_700_000_000), pendingMessageIds: ["m1"])
    ]
    try store.save(statesOfA, account: "a@example.com")
    try store.save(["仕事": NotificationRuleState(pendingMessageIds: ["m2"])], account: "b@example.com")

    #expect(try store.load(account: "a@example.com") == statesOfA)
    #expect(try store.load(account: "b@example.com")["仕事"]?.pendingMessageIds == ["m2"])
}
