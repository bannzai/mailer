import Foundation

/// ラベル即分けの振り分け条件。フィルタ条件と既存メール検索クエリの両方に変換できる。
public enum QuickLabelCondition: Sendable, Equatable {
    case fromAddress(String)
    case fromDomain(String)
    case subjectContains(String)

    public var filterCriteria: GmailFilterCriteria {
        switch self {
        case .fromAddress(let address):
            return GmailFilterCriteria(from: address)
        case .fromDomain(let domain):
            return GmailFilterCriteria(from: domain)
        case .subjectContains(let text):
            return GmailFilterCriteria(subject: text)
        }
    }

    public var searchQuery: String {
        switch self {
        case .fromAddress(let address):
            return "from:\(address)"
        case .fromDomain(let domain):
            return "from:\(domain)"
        case .subjectContains(let text):
            return "subject:(\(text))"
        }
    }
}

public struct QuickLabelResult: Sendable, Equatable {
    public let label: GmailLabel
    /// 既に同等のフィルタが存在した場合は false。
    public let filterCreated: Bool
    /// ラベル付与 + INBOX 除去を適用した既存メールの件数。
    public let movedMessageCount: Int
}

extension GmailClient {
    /// ラベル即分け: ラベル作成 + フィルタ作成 + 既存一致メールの移動を1オペレーションで行う。
    /// ラベル・フィルタは存在すれば再利用し、batchModify は冪等なため再実行しても安全。
    public func quickLabel(
        condition: QuickLabelCondition,
        labelName: String
    ) async throws -> QuickLabelResult {
        let label = try await findOrCreateLabel(name: labelName)

        let criteria = condition.filterCriteria
        let action = GmailFilterAction(addLabelIds: [label.id], removeLabelIds: ["INBOX"])
        let alreadyExists = try await listFilters().contains {
            $0.criteria == criteria && $0.action == action
        }
        if !alreadyExists {
            try await createFilter(criteria: criteria, action: action)
        }

        let refs = try await listAllMessages(query: condition.searchQuery)
        if !refs.isEmpty {
            try await batchModify(ids: refs.map(\.id), addLabelIds: [label.id], removeLabelIds: ["INBOX"])
        }
        return QuickLabelResult(
            label: label,
            filterCreated: !alreadyExists,
            movedMessageCount: refs.count
        )
    }
}

/// From ヘッダ ("表示名 <addr@example.com>" 形式) からメールアドレスを取り出す。
public enum EmailAddress {
    public static func extract(fromHeader headerValue: String) -> String? {
        if let openBracket = headerValue.lastIndex(of: "<"),
            let closeBracket = headerValue[openBracket...].firstIndex(of: ">")
        {
            let address = headerValue[headerValue.index(after: openBracket)..<closeBracket]
                .trimmingCharacters(in: .whitespaces)
            return address.contains("@") ? address : nil
        }
        let trimmed = headerValue.trimmingCharacters(in: .whitespaces)
        return trimmed.contains("@") ? trimmed : nil
    }

    public static func domain(of address: String) -> String? {
        let parts = address.split(separator: "@")
        return parts.count == 2 ? String(parts[1]) : nil
    }
}
