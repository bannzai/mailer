import Foundation

/// 1 通の問い合わせメールに対する Jev の判定結果。メール ID に紐付けて保存する。
/// 本文は保存しない (Gmail 側が正で、保存すると個人情報を設定ディレクトリに複製することになるため)。
public struct InquiryClassification: Codable, Sendable, Equatable {
    /// 種別 (質問定義の category の選択肢名)。
    public let category: String
    /// 種別の確信度 (0〜1)。
    public let categoryConfidence: Double
    /// 深刻度の段階名 (質問定義の severity.levels のうち、score を丸めた添字のもの)。
    public let severity: String
    /// 深刻度のスコア (levels の添字に対応する実数)。
    public let severityScore: Double
    /// 深刻度の確信度 (0〜1)。
    public let severityConfidence: Double
    /// flag 名ごとの該当確率 (0〜1)。
    public let flags: [String: Double]
    /// 判定したモデル ID。
    public let model: String
    /// 判定した時刻。
    public let classifiedAt: Date

    public init(
        category: String,
        categoryConfidence: Double,
        severity: String,
        severityScore: Double,
        severityConfidence: Double,
        flags: [String: Double],
        model: String,
        classifiedAt: Date
    ) {
        self.category = category
        self.categoryConfidence = categoryConfidence
        self.severity = severity
        self.severityScore = severityScore
        self.severityConfidence = severityConfidence
        self.flags = flags
        self.model = model
        self.classifiedAt = classifiedAt
    }

    /// 採用帯にある flag の名前 (名前順)。
    public var adoptedFlags: [String] {
        flags.filter { InquiryClassificationBand(probability: $0.value) == .adopted }.keys.sorted()
    }
}

/// 確率を「採用 / 不確実 / 却下」の 3 帯に分ける。不確実帯の判定は通知枠の条件に使わず、既存の通知経路に流す。
public enum InquiryClassificationBand: Sendable, Equatable {
    case adopted
    case uncertain
    case rejected

    /// 採用とみなす確率の下限。jev-decide の判定鎖と同じ 0.7 / 0.3 (TypeSafe 公式の confidence 3 段階に合わせた値。
    /// ~/.claude/documents/adr/0072-decision-chain-runner-jev-decide-with-three-band-thresholds.md)。
    public static let adoptedThreshold = 0.7
    /// 却下とみなす確率の上限。adoptedThreshold と同じ出典。
    public static let rejectedThreshold = 0.3

    public init(probability: Double) {
        if probability >= Self.adoptedThreshold {
            self = .adopted
        } else if probability <= Self.rejectedThreshold {
            self = .rejected
        } else {
            self = .uncertain
        }
    }
}

/// 判定結果を classifications.json にアカウント別・メール ID 別に永続化する。
/// メール ID は Gmail アカウントごとに独立しているためアカウント単位で持つ。
public struct InquiryClassificationStore: Sendable {
    /// 保存先の classifications.json。
    let fileURL: URL

    public init(directory: URL = MailerPaths.configDirectory) {
        self.fileURL = directory.appendingPathComponent("classifications.json")
    }

    /// 指定アカウントの判定結果 (メール ID -> 判定結果)。ファイルもアカウントの記録も無ければ空。
    public func load(account: String) throws -> [String: InquiryClassification] {
        try loadAllAccounts()[account] ?? [:]
    }

    /// 他アカウントの記録は保持したまま、指定アカウントの記録だけを置き換える。
    public func save(_ classifications: [String: InquiryClassification], account: String) throws {
        var allAccounts = try loadAllAccounts()
        allAccounts[account] = classifications
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(allAccounts).write(to: fileURL, options: .atomic)
    }

    /// ファイル全体の形は [アカウント email: [メール ID: InquiryClassification]]。
    private func loadAllAccounts() throws -> [String: [String: InquiryClassification]] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return [:]
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([String: [String: InquiryClassification]].self, from: Data(contentsOf: fileURL))
    }
}
