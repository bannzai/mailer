import Foundation

/// 通知枠の永続化操作で起きるエラー。
public enum NotificationRuleStoreError: Error, LocalizedError, Equatable {
    /// 指定した名前の枠が登録されていない。
    case unknownRule(String)

    public var errorDescription: String? {
        switch self {
        case .unknownRule(let name):
            return "通知枠 \(name) は登録されていません。"
        }
    }
}

/// 枠定義を notification-rules.json に永続化する。CLI とアプリで共有する。
public struct NotificationRuleStore: Sendable {
    let fileURL: URL

    public init(directory: URL = MailerPaths.configDirectory) {
        self.fileURL = directory.appendingPathComponent("notification-rules.json")
    }

    /// 枠定義を並び順のまま読み込む。ファイルが無ければ空。
    public func load() throws -> [NotificationRule] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([NotificationRule].self, from: Data(contentsOf: fileURL))
    }

    /// 枠定義を並び順のまま書き込む (並び順が評価順になる)。
    public func save(_ rules: [NotificationRule]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(rules).write(to: fileURL, options: .atomic)
    }

    /// 枠を追加する。同名の枠があれば置き換える (冪等)。
    public func add(_ rule: NotificationRule) throws {
        var rules = try load()
        if let index = rules.firstIndex(where: { $0.name == rule.name }) {
            rules[index] = rule
        } else {
            rules.append(rule)
        }
        try save(rules)
    }

    /// 枠を削除する。存在しなければ NotificationRuleStoreError.unknownRule を投げる。
    public func remove(name: String) throws {
        var rules = try load()
        guard let index = rules.firstIndex(where: { $0.name == name }) else {
            throw NotificationRuleStoreError.unknownRule(name)
        }
        rules.remove(at: index)
        try save(rules)
    }
}

/// 枠ごとの通知状態を notification-state.json にアカウント別に永続化する。
/// メール ID は Gmail アカウントごとに独立しているためアカウント単位で持つ。
public struct NotificationStateStore: Sendable {
    let fileURL: URL

    public init(directory: URL = MailerPaths.configDirectory) {
        self.fileURL = directory.appendingPathComponent("notification-state.json")
    }

    /// 指定アカウントの枠ごとの状態。ファイルもアカウントの記録も無ければ空。
    public func load(account: String) throws -> [String: NotificationRuleState] {
        try loadAllAccounts()[account] ?? [:]
    }

    /// 他アカウントの状態は保持したまま、指定アカウントの状態だけを置き換える。
    public func save(_ states: [String: NotificationRuleState], account: String) throws {
        var allAccounts = try loadAllAccounts()
        allAccounts[account] = states
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(allAccounts).write(to: fileURL, options: .atomic)
    }

    /// ファイル全体の形は [アカウント email: [枠名: NotificationRuleState]]。
    private func loadAllAccounts() throws -> [String: [String: NotificationRuleState]] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return [:]
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([String: [String: NotificationRuleState]].self, from: Data(contentsOf: fileURL))
    }
}
