import Foundation

@testable import MailerCore

final class MockTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var recordedRequests: [URLRequest] = []
    private let handler: @Sendable (URLRequest) throws -> (Data, HTTPURLResponse)

    init(handler: @escaping @Sendable (URLRequest) throws -> (Data, HTTPURLResponse)) {
        self.handler = handler
    }

    var requests: [URLRequest] {
        lock.withLock { recordedRequests }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { recordedRequests.append(request) }
        return try handler(request)
    }
}

func httpResponse(url: URL, statusCode: Int) -> HTTPURLResponse {
    HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: nil)!
}

extension URLRequest {
    var formBody: [String: String] {
        guard let httpBody, let string = String(data: httpBody, encoding: .utf8) else {
            return [:]
        }
        var result: [String: String] = [:]
        for pair in string.components(separatedBy: "&") {
            let parts = pair.components(separatedBy: "=")
            guard parts.count == 2 else { continue }
            result[parts[0].removingPercentEncoding ?? parts[0]] = parts[1].removingPercentEncoding ?? parts[1]
        }
        return result
    }
}
