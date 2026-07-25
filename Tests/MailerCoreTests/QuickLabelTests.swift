import Foundation
import Testing

@testable import MailerCore

@Test func quickLabelConditionMapsToCriteriaAndQuery() {
    #expect(QuickLabelCondition.fromAddress("news@example.com").filterCriteria == GmailFilterCriteria(from: "news@example.com"))
    #expect(QuickLabelCondition.fromAddress("news@example.com").searchQuery == "from:news@example.com")
    #expect(QuickLabelCondition.fromDomain("example.com").filterCriteria == GmailFilterCriteria(from: "example.com"))
    #expect(QuickLabelCondition.fromDomain("example.com").searchQuery == "from:example.com")
    #expect(QuickLabelCondition.subjectContains("請求書").filterCriteria == GmailFilterCriteria(subject: "請求書"))
    #expect(QuickLabelCondition.subjectContains("請求書").searchQuery == "subject:(請求書)")
}

@Test func quickLabelCreatesLabelFilterAndMovesExistingMessages() async throws {
    let (client, transport) = makeGmailTestClient(gmailResponses: [
        (200, #"{"labels": []}"#),
        (200, #"{"id": "Label_9", "name": "newsletter"}"#),
        (200, #"{}"#),
        (200, #"{"id": "filter-1", "criteria": {"from": "news@example.com"}, "action": {"addLabelIds": ["Label_9"], "removeLabelIds": ["INBOX"]}}"#),
        (200, #"{"messages": [{"id": "m-1", "threadId": "t-1"}, {"id": "m-2", "threadId": "t-2"}]}"#),
        (204, ""),
    ])
    let result = try await client.quickLabel(condition: .fromAddress("news@example.com"), labelName: "newsletter")

    #expect(result.label.id == "Label_9")
    #expect(result.filterCreated == true)
    #expect(result.movedMessageCount == 2)

    let requests = gmailTestRequests(transport)
    #expect(requests.count == 6)

    let createdFilter = try JSONDecoder().decode(GmailFilter.self, from: requests[3].httpBody ?? Data())
    #expect(createdFilter.criteria == GmailFilterCriteria(from: "news@example.com"))
    #expect(createdFilter.action == GmailFilterAction(addLabelIds: ["Label_9"], removeLabelIds: ["INBOX"]))

    let batchModify = try JSONDecoder().decode(BatchModifyRequest.self, from: requests[5].httpBody ?? Data())
    #expect(batchModify.ids == ["m-1", "m-2"])
    #expect(batchModify.addLabelIds == ["Label_9"])
    #expect(batchModify.removeLabelIds == ["INBOX"])
}

@Test func quickLabelRerunIsIdempotent() async throws {
    let (client, transport) = makeGmailTestClient(gmailResponses: [
        (200, #"{"labels": [{"id": "Label_9", "name": "newsletter"}]}"#),
        (
            200,
            #"{"filter": [{"id": "filter-1", "criteria": {"from": "news@example.com"}, "action": {"addLabelIds": ["Label_9"], "removeLabelIds": ["INBOX"]}}]}"#
        ),
        (200, #"{}"#),
    ])
    let result = try await client.quickLabel(condition: .fromAddress("news@example.com"), labelName: "newsletter")

    #expect(result.filterCreated == false)
    #expect(result.movedMessageCount == 0)
    let requests = gmailTestRequests(transport)
    #expect(requests.count == 3)
    #expect(requests.allSatisfy { $0.httpMethod == "GET" })
}

@Test func filterListDecodesSingularKey() async throws {
    let (client, _) = makeGmailTestClient(gmailResponses: [
        (200, #"{"filter": [{"id": "f-1", "criteria": {"from": "a@b.com"}, "action": {"addLabelIds": ["L1"]}}]}"#)
    ])
    let filters = try await client.listFilters()
    #expect(filters.count == 1)
    #expect(filters[0].id == "f-1")
}

@Test func emailAddressExtractionHandlesDisplayNameFormats() {
    #expect(EmailAddress.extract(fromHeader: "News <news@example.com>") == "news@example.com")
    #expect(EmailAddress.extract(fromHeader: "\"Bann, Zai\" <bannzai@example.com>") == "bannzai@example.com")
    #expect(EmailAddress.extract(fromHeader: "plain@example.com") == "plain@example.com")
    #expect(EmailAddress.extract(fromHeader: "壊れたヘッダ") == nil)
    #expect(EmailAddress.domain(of: "news@example.com") == "example.com")
    #expect(EmailAddress.domain(of: "invalid") == nil)
}
