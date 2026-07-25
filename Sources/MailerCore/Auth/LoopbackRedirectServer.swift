import Foundation

public struct SocketError: Error, LocalizedError {
    public let operation: String
    public let code: Int32

    public var errorDescription: String? {
        "socket \(operation) に失敗しました: \(String(cString: strerror(code)))"
    }
}

/// CLI の認可フローで loopback リダイレクトを受けるための使い捨て HTTP サーバ。
/// 127.0.0.1 の空きポートで待ち受け、最初の認可コールバック 1 件だけを受理する。
/// Network.framework はサンドボックス環境で listen できないことがあるため BSD ソケットで実装する。
public final class LoopbackRedirectServer: @unchecked Sendable {
    public struct Callback: Sendable, Equatable {
        public let code: String
        public let state: String
    }

    public let port: UInt16
    private let listeningSocket: Int32
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Callback, Error>?
    private var pendingResult: Result<Callback, Error>?
    private var stopped = false

    public var redirectURI: String {
        "http://127.0.0.1:\(port)/oauth/callback"
    }

    public static func start() throws -> LoopbackRedirectServer {
        let socketFD = socket(AF_INET, SOCK_STREAM, 0)
        guard socketFD >= 0 else {
            throw SocketError(operation: "create", code: errno)
        }
        var enable: Int32 = 1
        setsockopt(socketFD, SOL_SOCKET, SO_REUSEADDR, &enable, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            let code = errno
            close(socketFD)
            throw SocketError(operation: "bind", code: code)
        }
        guard listen(socketFD, 5) == 0 else {
            let code = errno
            close(socketFD)
            throw SocketError(operation: "listen", code: code)
        }

        var boundAddress = sockaddr_in()
        var addressLength = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &boundAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(socketFD, $0, &addressLength)
            }
        }
        guard nameResult == 0 else {
            let code = errno
            close(socketFD)
            throw SocketError(operation: "getsockname", code: code)
        }

        let server = LoopbackRedirectServer(
            listeningSocket: socketFD,
            port: UInt16(bigEndian: boundAddress.sin_port)
        )
        server.runAcceptLoop()
        return server
    }

    private init(listeningSocket: Int32, port: UInt16) {
        self.listeningSocket = listeningSocket
        self.port = port
    }

    /// 認可コールバックを待つ。ブラウザでの認可が完了するまで返らない。
    public func waitForCallback() async throws -> Callback {
        try await withCheckedThrowingContinuation { continuation in
            let delivered: Result<Callback, Error>? = lock.withLock {
                if let pendingResult {
                    self.pendingResult = nil
                    return pendingResult
                }
                self.continuation = continuation
                return nil
            }
            if let delivered {
                continuation.resume(with: delivered)
            }
        }
    }

    public func stop() {
        let continuation: CheckedContinuation<Callback, Error>? = lock.withLock {
            guard !stopped else { return nil }
            stopped = true
            let continuation = self.continuation
            self.continuation = nil
            return continuation
        }
        shutdown(listeningSocket, SHUT_RDWR)
        close(listeningSocket)
        continuation?.resume(throwing: OAuthError.redirectServerClosed)
    }

    private var isStopped: Bool {
        lock.withLock { stopped }
    }

    private func runAcceptLoop() {
        Thread.detachNewThread { [self] in
            while true {
                let connection = accept(listeningSocket, nil, nil)
                guard connection >= 0 else {
                    return
                }
                handleConnection(connection)
                if isStopped {
                    return
                }
            }
        }
    }

    private func handleConnection(_ connection: Int32) {
        defer { close(connection) }
        var requestData = Data()
        var chunk = [UInt8](repeating: 0, count: 16 * 1024)
        let headerTerminator = Data("\r\n\r\n".utf8)
        while requestData.range(of: headerTerminator) == nil, requestData.count < 64 * 1024 {
            let received = recv(connection, &chunk, chunk.count, 0)
            guard received > 0 else { return }
            requestData.append(contentsOf: chunk[0..<received])
        }

        let requestLine = String(decoding: requestData, as: UTF8.self)
            .components(separatedBy: "\r\n")
            .first ?? ""
        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2,
            let components = URLComponents(string: "http://127.0.0.1\(parts[1])"),
            components.path == "/oauth/callback"
        else {
            respond(connection, status: "404 Not Found", body: "Not Found")
            return
        }
        let queryValue = { (name: String) in components.queryItems?.first { $0.name == name }?.value }
        if let errorValue = queryValue("error") {
            respond(connection, status: "200 OK", body: Self.errorPage(reason: errorValue))
            finish(.failure(OAuthError.authorizationDenied(errorValue)))
            return
        }
        guard let code = queryValue("code"), let state = queryValue("state") else {
            respond(connection, status: "400 Bad Request", body: "Bad Request")
            return
        }
        respond(connection, status: "200 OK", body: Self.successPage)
        finish(.success(Callback(code: code, state: state)))
    }

    private func finish(_ result: Result<Callback, Error>) {
        let continuation: CheckedContinuation<Callback, Error>? = lock.withLock {
            if let continuation = self.continuation {
                self.continuation = nil
                return continuation
            }
            if pendingResult == nil {
                pendingResult = result
            }
            return nil
        }
        continuation?.resume(with: result)
    }

    private func respond(_ connection: Int32, status: String, body: String) {
        let bodyData = Data(body.utf8)
        let header =
            "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(bodyData.count)\r\nConnection: close\r\n\r\n"
        var response = Data(header.utf8)
        response.append(bodyData)
        response.withUnsafeBytes { buffer in
            var sent = 0
            while sent < buffer.count {
                let result = send(connection, buffer.baseAddress! + sent, buffer.count - sent, 0)
                guard result > 0 else { return }
                sent += result
            }
        }
    }

    static let successPage = """
        <html><meta charset="utf-8"><body style="font-family: sans-serif; text-align: center; padding-top: 4em;">
        <h1>認可が完了しました</h1><p>このタブを閉じてターミナルに戻ってください。</p></body></html>
        """

    static func errorPage(reason: String) -> String {
        """
        <html><meta charset="utf-8"><body style="font-family: sans-serif; text-align: center; padding-top: 4em;">
        <h1>認可に失敗しました</h1><p>\(reason)</p></body></html>
        """
    }
}
