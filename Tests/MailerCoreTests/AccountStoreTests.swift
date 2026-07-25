import Foundation
import Testing

@testable import MailerCore

private func makeStore() -> AccountStore {
    AccountStore(
        directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("mailer-tests-\(UUID().uuidString)", isDirectory: true)
    )
}

@Test func firstAddedAccountBecomesDefault() throws {
    let store = makeStore()
    try store.add(email: "a@example.com")
    try store.add(email: "b@example.com")
    let list = try store.load()
    #expect(list.defaultAccount == "a@example.com")
    #expect(list.accounts.map(\.email) == ["a@example.com", "b@example.com"])
}

@Test func addIsIdempotent() throws {
    let store = makeStore()
    try store.add(email: "a@example.com")
    try store.add(email: "a@example.com")
    #expect(try store.load().accounts.count == 1)
}

@Test func removingDefaultPromotesNextAccount() throws {
    let store = makeStore()
    try store.add(email: "a@example.com")
    try store.add(email: "b@example.com")
    try store.remove(email: "a@example.com")
    let list = try store.load()
    #expect(list.defaultAccount == "b@example.com")
    #expect(list.accounts.map(\.email) == ["b@example.com"])
}

@Test func setDefaultRejectsUnknownAccount() throws {
    let store = makeStore()
    try store.add(email: "a@example.com")
    #expect(throws: AccountStoreError.unknownAccount("x@example.com")) {
        try store.setDefault(email: "x@example.com")
    }
}

@Test func resolveAccountPrefersExplicitAndFallsBackToDefault() throws {
    let store = makeStore()
    try store.add(email: "a@example.com")
    try store.add(email: "b@example.com")
    #expect(try store.resolveAccount("b@example.com") == "b@example.com")
    #expect(try store.resolveAccount(nil) == "a@example.com")
    #expect(throws: AccountStoreError.unknownAccount("x@example.com")) {
        _ = try store.resolveAccount("x@example.com")
    }
}
