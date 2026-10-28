import Foundation

/// 通知枠の永続化操作で起きるエラー。
public enum NotificationRuleStoreError: Error, LocalizedError, Equatable {
    /// 指定した名前の枠が登録されていない。
    case unknownRule(String)
    /// 同じ名前の枠が複数ある。状態は名前をキーに持つため、同名の枠は保存も読み込みも受け付けない。
    case duplicateRuleName(String)

    public var errorDescription: String? {
        switch self {
        case .unknownRule(let name):
            return "通知枠 \(name) は登録されていません。"
        case .duplicateRuleName(let name):
            return "通知枠 \(name) が複数あります。名前は一意にしてください。"
        }
    }
}

/// 同名の枠があれば NotificationRuleStoreError.duplicateRuleName を投げる。
private func validateUniqueNames(rules: [NotificationRule]) throws {
    var seenNames: Set<String> = []
    for rule in rules where !seenNames.insert(rule.name).inserted {
        throw NotificationRuleStoreError.duplicateRuleName(rule.name)
    }
}

/// 枠定義を notification-rules.json に永続化する。CLI とアプリで共有する。
public struct NotificationRuleStore: Sendable {
    /// 保存先の notification-rules.json。
    let fileURL: URL

    public init(directory: URL = MailerPaths.configDirectory) {
        self.fileURL = directory.appendingPathComponent("notification-rules.json")
    }

    /// 枠定義を並び順のまま読み込む。ファイルが無ければ空。手で編集して同名の枠が入ったファイルは投げる。
    public func load() throws -> [NotificationRule] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let rules = try decoder.decode([NotificationRule].self, from: Data(contentsOf: fileURL))
        try validateUniqueNames(rules: rules)
        return rules
    }

    /// 枠定義を並び順のまま書き込む (並び順が評価順になる)。同名の枠があれば投げる。
    public func save(rules: [NotificationRule]) throws {
        try validateUniqueNames(rules: rules)
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
    public func add(rule: NotificationRule) throws {
        var rules = try load()
        if let index = rules.firstIndex(where: { $0.name == rule.name }) {
            rules[index] = rule
        } else {
            rules.append(rule)
        }
        try save(rules: rules)
    }

    /// 枠を削除する。存在しなければ NotificationRuleStoreError.unknownRule を投げる。
    public func remove(name: String) throws {
        var rules = try load()
        guard let index = rules.firstIndex(where: { $0.name == name }) else {
            throw NotificationRuleStoreError.unknownRule(name)
        }
        rules.remove(at: index)
        try save(rules: rules)
    }
}

/// 枠ごとの通知状態を notification-state.json にアカウント別に永続化する。
/// メール ID は Gmail アカウントごとに独立しているためアカウント単位で持つ。
public struct NotificationStateStore: Sendable {
    /// 保存先の notification-state.json。
    let fileURL: URL

    public init(directory: URL = MailerPaths.configDirectory) {
        self.fileURL = directory.appendingPathComponent("notification-state.json")
    }

    /// 指定アカウントの枠ごとの状態。ファイルもアカウントの記録も無ければ空。
    public func load(account: String) throws -> [String: NotificationRuleState] {
        try loadAllAccounts()[account] ?? [:]
    }

    /// 他アカウントの状態は保持したまま、指定アカウントの状態だけを置き換える。
    public func save(states: [String: NotificationRuleState], account: String) throws {
        try write(allAccounts: try loadAllAccounts().merging([account: states]) { _, new in new })
    }

    /// 指定アカウントの状態を消す (アカウント削除時に呼ぶ。同じアドレスで再追加した時に古い保留と時計が残らないようにする)。
    /// 記録が無ければ何もしない (冪等)。
    public func remove(account: String) throws {
        var allAccounts = try loadAllAccounts()
        guard allAccounts.removeValue(forKey: account) != nil else {
            return
        }
        try write(allAccounts: allAccounts)
    }

    /// ファイル全体を書き戻す。
    private func write(allAccounts: [String: [String: NotificationRuleState]]) throws {
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
