import Foundation
import Testing

@testable import MailerCore

@Test func classificationStoreReturnsEmptyWithoutFile() throws {
    #expect(try makeInquiryTestStore().load(account: "a@example.com").isEmpty)
}

@Test func classificationStoreRoundTripsPerAccount() throws {
    let store = makeInquiryTestStore()
    let first = makeInquiryClassification()
    let second = makeInquiryClassification(
        category: "praise", categoryConfidence: 0.8, severity: "none", severityScore: 0.1)
    try store.save(["m1": first], account: "a@example.com")
    try store.save(["m2": second], account: "b@example.com")

    #expect(try store.load(account: "a@example.com") == ["m1": first])
    #expect(try store.load(account: "b@example.com") == ["m2": second])
}

@Test func classificationStoreKeepsOtherAccountsOnSave() throws {
    let store = makeInquiryTestStore()
    try store.save(["m1": makeInquiryClassification()], account: "a@example.com")
    try store.save(["m2": makeInquiryClassification()], account: "b@example.com")
    try store.save([:], account: "a@example.com")

    #expect(try store.load(account: "a@example.com").isEmpty)
    #expect(try store.load(account: "b@example.com").keys.sorted() == ["m2"])
}

@Test func classificationJSONDoesNotContainMailText() throws {
    let store = makeInquiryTestStore()
    try store.save(["m1": makeInquiryClassification()], account: "a@example.com")
    let json = try String(contentsOf: store.fileURL, encoding: .utf8)
    #expect(json.contains("\"category\" : \"bug\""))
    #expect(!json.contains("text"))
    #expect(!json.contains("body"))
}
