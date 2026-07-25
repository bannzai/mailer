import Foundation

/// Gmail API (users.*) の薄いクライアント。
/// 401 はトークン強制リフレッシュ後に1回だけ再試行し、429/5xx は指数バックオフで再試行する。
public struct GmailClient: Sendable {
    static let baseURL = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me")!
    /// batchModify が1リクエストで受け付ける messageIds の上限。
    public static let batchModifyLimit = 1000

    public let email: String
    let tokenProvider: TokenProvider
    let transport: HTTPTransport
    /// 429/5xx 再試行の待機秒数。要素数が最大再試行回数になる。テストでは 0 を注入する。
    let retryDelays: [TimeInterval]

    public init(
        email: String,
        tokenProvider: TokenProvider,
        transport: HTTPTransport = URLSessionTransport(),
        retryDelays: [TimeInterval] = [0.5, 1, 2, 4]
    ) {
        self.email = email
        self.tokenProvider = tokenProvider
        self.transport = transport
        self.retryDelays = retryDelays
    }

    // MARK: - users.getProfile

    public func getProfile() async throws -> GmailProfile {
        try await execute(method: "GET", path: "profile")
    }

    // MARK: - users.messages

    public func listMessages(
        query: String? = nil,
        labelIds: [String] = [],
        maxResults: Int? = nil,
        pageToken: String? = nil
    ) async throws -> MessageList {
        var queryItems: [URLQueryItem] = []
        if let query {
            queryItems.append(URLQueryItem(name: "q", value: query))
        }
        queryItems.append(contentsOf: labelIds.map { URLQueryItem(name: "labelIds", value: $0) })
        if let maxResults {
            queryItems.append(URLQueryItem(name: "maxResults", value: String(maxResults)))
        }
        if let pageToken {
            queryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
        }
        return try await execute(method: "GET", path: "messages", queryItems: queryItems)
    }

    /// 全ページを辿って一致するメッセージ参照を集める。
    public func listAllMessages(query: String? = nil, labelIds: [String] = []) async throws -> [GmailMessageRef] {
        try await collectAllPages { pageToken in
            let page = try await listMessages(query: query, labelIds: labelIds, maxResults: 500, pageToken: pageToken)
            return (page.messages ?? [], page.nextPageToken)
        }
    }

    public enum MessageFormat: Sendable {
        case full
        case minimal
        case metadata(headers: [String])

        var queryItems: [URLQueryItem] {
            switch self {
            case .full:
                return [URLQueryItem(name: "format", value: "full")]
            case .minimal:
                return [URLQueryItem(name: "format", value: "minimal")]
            case .metadata(let headers):
                return [URLQueryItem(name: "format", value: "metadata")]
                    + headers.map { URLQueryItem(name: "metadataHeaders", value: $0) }
            }
        }
    }

    public func getMessage(id: String, format: MessageFormat = .full) async throws -> GmailMessage {
        try await execute(method: "GET", path: "messages/\(id)", queryItems: format.queryItems)
    }

    @discardableResult
    public func modifyMessage(
        id: String,
        addLabelIds: [String] = [],
        removeLabelIds: [String] = []
    ) async throws -> GmailMessage {
        try await execute(
            method: "POST",
            path: "messages/\(id)/modify",
            body: ModifyRequest(addLabelIds: addLabelIds, removeLabelIds: removeLabelIds)
        )
    }

    /// 最大1,000件ずつに分割して batchModify を呼ぶ。付与済みラベルの再付与はエラーにならないため冪等。
    public func batchModify(
        ids: [String],
        addLabelIds: [String] = [],
        removeLabelIds: [String] = []
    ) async throws {
        for chunk in stride(from: 0, to: ids.count, by: Self.batchModifyLimit)
            .map({ Array(ids[$0..<min($0 + Self.batchModifyLimit, ids.count)]) })
        {
            try await executeNoContent(
                method: "POST",
                path: "messages/batchModify",
                body: BatchModifyRequest(ids: chunk, addLabelIds: addLabelIds, removeLabelIds: removeLabelIds)
            )
        }
    }

    @discardableResult
    public func trashMessage(id: String) async throws -> GmailMessage {
        try await execute(method: "POST", path: "messages/\(id)/trash")
    }

    // MARK: - users.labels

    public func listLabels() async throws -> [GmailLabel] {
        let list: LabelList = try await execute(method: "GET", path: "labels")
        return list.labels ?? []
    }

    public func createLabel(
        name: String,
        labelListVisibility: String = "labelShow",
        messageListVisibility: String = "show"
    ) async throws -> GmailLabel {
        try await execute(
            method: "POST",
            path: "labels",
            body: CreateLabelRequest(
                name: name,
                labelListVisibility: labelListVisibility,
                messageListVisibility: messageListVisibility
            )
        )
    }

    public func updateLabel(id: String, name: String) async throws -> GmailLabel {
        try await execute(method: "PUT", path: "labels/\(id)", body: ["name": name])
    }

    public func deleteLabel(id: String) async throws {
        try await executeNoContent(method: "DELETE", path: "labels/\(id)")
    }

    // MARK: - users.threads

    public func listThreads(
        query: String? = nil,
        labelIds: [String] = [],
        maxResults: Int? = nil,
        pageToken: String? = nil
    ) async throws -> ThreadList {
        var queryItems: [URLQueryItem] = []
        if let query {
            queryItems.append(URLQueryItem(name: "q", value: query))
        }
        queryItems.append(contentsOf: labelIds.map { URLQueryItem(name: "labelIds", value: $0) })
        if let maxResults {
            queryItems.append(URLQueryItem(name: "maxResults", value: String(maxResults)))
        }
        if let pageToken {
            queryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
        }
        return try await execute(method: "GET", path: "threads", queryItems: queryItems)
    }

    public func getThread(id: String) async throws -> GmailThread {
        try await execute(method: "GET", path: "threads/\(id)")
    }

    @discardableResult
    public func modifyThread(
        id: String,
        addLabelIds: [String] = [],
        removeLabelIds: [String] = []
    ) async throws -> GmailThread {
        try await execute(
            method: "POST",
            path: "threads/\(id)/modify",
            body: ModifyRequest(addLabelIds: addLabelIds, removeLabelIds: removeLabelIds)
        )
    }

    // MARK: - users.history

    public func listHistory(
        startHistoryId: String,
        historyTypes: [String] = [],
        pageToken: String? = nil
    ) async throws -> HistoryList {
        var queryItems = [URLQueryItem(name: "startHistoryId", value: startHistoryId)]
        queryItems.append(contentsOf: historyTypes.map { URLQueryItem(name: "historyTypes", value: $0) })
        if let pageToken {
            queryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
        }
        return try await execute(method: "GET", path: "history", queryItems: queryItems)
    }

    // MARK: - 共通処理

    /// nextPageToken が尽きるまで fetch を繰り返して要素を集める。
    public func collectAllPages<Element: Sendable>(
        fetch: (String?) async throws -> ([Element], String?)
    ) async throws -> [Element] {
        var collected: [Element] = []
        var pageToken: String? = nil
        repeat {
            let (items, nextPageToken) = try await fetch(pageToken)
            collected.append(contentsOf: items)
            pageToken = nextPageToken
        } while pageToken != nil
        return collected
    }

    private func execute<Response: Decodable>(
        method: String,
        path: String,
        queryItems: [URLQueryItem] = []
    ) async throws -> Response {
        let data = try await executeRaw(method: method, path: path, queryItems: queryItems, bodyData: nil)
        return try JSONDecoder().decode(Response.self, from: data)
    }

    private func execute<Response: Decodable>(
        method: String,
        path: String,
        queryItems: [URLQueryItem] = [],
        body: some Encodable & Sendable
    ) async throws -> Response {
        let data = try await executeRaw(
            method: method,
            path: path,
            queryItems: queryItems,
            bodyData: try JSONEncoder().encode(body)
        )
        return try JSONDecoder().decode(Response.self, from: data)
    }

    private func executeNoContent(
        method: String,
        path: String,
        queryItems: [URLQueryItem] = []
    ) async throws {
        _ = try await executeRaw(method: method, path: path, queryItems: queryItems, bodyData: nil)
    }

    private func executeNoContent(
        method: String,
        path: String,
        queryItems: [URLQueryItem] = [],
        body: some Encodable & Sendable
    ) async throws {
        _ = try await executeRaw(
            method: method,
            path: path,
            queryItems: queryItems,
            bodyData: try JSONEncoder().encode(body)
        )
    }

    private func executeRaw(
        method: String,
        path: String,
        queryItems: [URLQueryItem],
        bodyData: Data?
    ) async throws -> Data {
        var components = URLComponents(
            url: Self.baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )!
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        if let bodyData {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = bodyData
        }

        var accessToken = try await tokenProvider.accessToken(for: email)
        var didRetryUnauthorized = false
        var retryIndex = 0
        while true {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await transport.send(request)
            switch response.statusCode {
            case 200..<300:
                return data
            case 401 where !didRetryUnauthorized:
                didRetryUnauthorized = true
                accessToken = try await tokenProvider.refreshedAccessToken(for: email)
            case 429, 500..<600:
                guard retryIndex < retryDelays.count else {
                    throw Self.apiError(statusCode: response.statusCode, data: data)
                }
                let delay = retryDelays[retryIndex]
                retryIndex += 1
                if delay > 0 {
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            default:
                throw Self.apiError(statusCode: response.statusCode, data: data)
            }
        }
    }

    static func apiError(statusCode: Int, data: Data) -> GmailAPIError {
        let body = try? JSONDecoder().decode(GmailAPIErrorBody.self, from: data)
        return GmailAPIError(
            statusCode: statusCode,
            message: body?.error?.message,
            status: body?.error?.status
        )
    }
}

struct ModifyRequest: Codable, Sendable {
    let addLabelIds: [String]
    let removeLabelIds: [String]
}

struct BatchModifyRequest: Codable, Sendable {
    let ids: [String]
    let addLabelIds: [String]
    let removeLabelIds: [String]
}

struct CreateLabelRequest: Codable, Sendable {
    let name: String
    let labelListVisibility: String
    let messageListVisibility: String
}
