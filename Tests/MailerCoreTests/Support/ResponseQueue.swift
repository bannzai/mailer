import Foundation

/// リクエスト順に返すレスポンスのキュー。ステートフルな再試行テストに使う。
final class ResponseQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [(statusCode: Int, body: String)]

    init(_ responses: [(statusCode: Int, body: String)]) {
        self.responses = responses
    }

    func next(for url: URL) throws -> (Data, HTTPURLResponse) {
        let response: (statusCode: Int, body: String)? = lock.withLock {
            responses.isEmpty ? nil : responses.removeFirst()
        }
        guard let response else {
            throw URLError(.resourceUnavailable)
        }
        return (Data(response.body.utf8), httpResponse(url: url, statusCode: response.statusCode))
    }
}
