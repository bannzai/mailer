import Foundation

public struct GmailMessageRef: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let threadId: String?
}

public struct MessageList: Codable, Sendable, Equatable {
    public let messages: [GmailMessageRef]?
    public let nextPageToken: String?
    public let resultSizeEstimate: Int?
}

public struct GmailHeader: Codable, Sendable, Equatable {
    public let name: String
    public let value: String
}

public struct GmailMessagePartBody: Codable, Sendable, Equatable {
    public let size: Int?
    /// base64url エンコードされた本文。
    public let data: String?
    /// 本文が大きい時に Gmail が data の代わりに返す添付 ID (users.messages.attachments.get で取得する)。
    public let attachmentId: String?

    /// attachmentId を省略できるようにするため手書きする (memberwise init は既定値を持てない。既存の呼び出しを変えないため)。
    public init(size: Int?, data: String?, attachmentId: String? = nil) {
        self.size = size
        self.data = data
        self.attachmentId = attachmentId
    }

    public var decodedData: Data? {
        guard let data else { return nil }
        var base64 =
            data
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 {
            base64.append("=")
        }
        return Data(base64Encoded: base64)
    }
}

public struct GmailMessagePart: Codable, Sendable, Equatable {
    public let partId: String?
    public let mimeType: String?
    public let filename: String?
    public let headers: [GmailHeader]?
    public let body: GmailMessagePartBody?
    public let parts: [GmailMessagePart]?

    /// MIME ツリーから最初に一致する mimeType のパートを深さ優先で探す。
    public func firstPart(mimeType target: String) -> GmailMessagePart? {
        if mimeType == target, body?.data != nil {
            return self
        }
        for part in parts ?? [] {
            if let found = part.firstPart(mimeType: target) {
                return found
            }
        }
        return nil
    }
}

public struct GmailMessage: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let threadId: String?
    public let labelIds: [String]?
    public let snippet: String?
    public let historyId: String?
    /// epoch ミリ秒の文字列。
    public let internalDate: String?
    public let payload: GmailMessagePart?
    public let sizeEstimate: Int?

    public var date: Date? {
        guard let internalDate, let milliseconds = Double(internalDate) else { return nil }
        return Date(timeIntervalSince1970: milliseconds / 1000)
    }

    public func headerValue(_ name: String) -> String? {
        payload?.headers?.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    public var from: String? { headerValue("From") }
    public var subject: String? { headerValue("Subject") }
    public var to: String? { headerValue("To") }
}

public struct GmailLabelColor: Codable, Sendable, Equatable {
    public let textColor: String?
    public let backgroundColor: String?
}

public struct GmailLabel: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let type: String?
    public let messageListVisibility: String?
    public let labelListVisibility: String?
    public let messagesTotal: Int?
    public let messagesUnread: Int?
    public let color: GmailLabelColor?
}

struct LabelList: Codable {
    let labels: [GmailLabel]?
}

public struct GmailThreadRef: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let snippet: String?
    public let historyId: String?
}

public struct ThreadList: Codable, Sendable, Equatable {
    public let threads: [GmailThreadRef]?
    public let nextPageToken: String?
    public let resultSizeEstimate: Int?
}

public struct GmailThread: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let historyId: String?
    public let messages: [GmailMessage]?
}

public struct HistoryMessageChange: Codable, Sendable, Equatable {
    public let message: GmailMessageRef?
    public let labelIds: [String]?
}

public struct HistoryRecord: Codable, Sendable, Equatable {
    public let id: String
    public let messages: [GmailMessageRef]?
    public let messagesAdded: [HistoryMessageChange]?
    public let messagesDeleted: [HistoryMessageChange]?
    public let labelsAdded: [HistoryMessageChange]?
    public let labelsRemoved: [HistoryMessageChange]?
}

public struct HistoryList: Codable, Sendable, Equatable {
    public let history: [HistoryRecord]?
    public let nextPageToken: String?
    public let historyId: String?
}

/// Gmail API のエラーレスポンス ({"error": {"code": ..., "message": ..., "status": ...}})。
public struct GmailAPIErrorBody: Codable, Sendable, Equatable {
    public struct Detail: Codable, Sendable, Equatable {
        public let code: Int?
        public let message: String?
        public let status: String?
    }
    public let error: Detail?
}

public struct GmailAPIError: Error, LocalizedError, Equatable {
    public let statusCode: Int
    public let message: String?
    public let status: String?

    public var errorDescription: String? {
        "Gmail API がエラーを返しました (HTTP \(statusCode)): \(message ?? status ?? "詳細不明")"
    }
}
