import Foundation

public struct GmailFilterCriteria: Codable, Sendable, Equatable {
    public var from: String?
    public var to: String?
    public var subject: String?
    public var query: String?

    public init(from: String? = nil, to: String? = nil, subject: String? = nil, query: String? = nil) {
        self.from = from
        self.to = to
        self.subject = subject
        self.query = query
    }
}

public struct GmailFilterAction: Codable, Sendable, Equatable {
    public var addLabelIds: [String]?
    public var removeLabelIds: [String]?

    public init(addLabelIds: [String]? = nil, removeLabelIds: [String]? = nil) {
        self.addLabelIds = addLabelIds
        self.removeLabelIds = removeLabelIds
    }
}

public struct GmailFilter: Codable, Sendable, Equatable {
    public let id: String?
    public let criteria: GmailFilterCriteria?
    public let action: GmailFilterAction?

    public init(id: String? = nil, criteria: GmailFilterCriteria?, action: GmailFilterAction?) {
        self.id = id
        self.criteria = criteria
        self.action = action
    }
}

/// users.settings.filters.list のレスポンスキーは "filter" (単数形)。
struct FilterList: Codable {
    let filter: [GmailFilter]?
}

extension GmailClient {
    // MARK: - users.settings.filters (gmail.settings.basic スコープが必要)

    public func listFilters() async throws -> [GmailFilter] {
        let list: FilterList = try await execute(method: "GET", path: "settings/filters")
        return list.filter ?? []
    }

    @discardableResult
    public func createFilter(
        criteria: GmailFilterCriteria,
        action: GmailFilterAction
    ) async throws -> GmailFilter {
        try await execute(
            method: "POST",
            path: "settings/filters",
            body: GmailFilter(criteria: criteria, action: action)
        )
    }

    public func deleteFilter(id: String) async throws {
        try await executeNoContent(method: "DELETE", path: "settings/filters/\(id)")
    }
}
