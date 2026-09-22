import Foundation

/// 問い合わせメールの分類に使う質問定義。castle の jev-check skill が持つ `review-triage.json` (SSOT) を読み込む。
/// 種別 (Choice)・flag (Noul)・深刻度 (Score) の 3 種類の質問を 1 リクエストにまとめる。
public struct InquiryRuleDefinition: Codable, Sendable, Equatable {
    /// 選択肢や true / false ごとの判定基準を持つ質問 (種別と flag)。
    public struct Question: Codable, Sendable, Equatable {
        /// Jev に渡す質問文。
        public let instructions: String
        /// 選択肢名 (flag では "true" / "false") ごとの判定基準。
        public let criteria: [String: String]

        public init(instructions: String, criteria: [String: String]) {
            self.instructions = instructions
            self.criteria = criteria
        }
    }

    /// 深刻度の質問。levels の並び順がスコアの 0, 1, 2, ... に対応する。
    public struct Severity: Codable, Sendable, Equatable {
        /// Jev に渡す質問文。
        public let instructions: String
        /// 深刻度の段階名 (低い順)。
        public let levels: [String]

        public init(instructions: String, levels: [String]) {
            self.instructions = instructions
            self.levels = levels
        }
    }

    /// castle 側が flag を「該当」とみなす確率の閾値。mailer の採用 / 不確実 / 却下の帯は InquiryClassificationBand が持ち、この値は使わない。
    public let threshold: Double
    /// castle 側が要注意とみなす flag の名前。
    public let attentionFlags: [String]
    /// 種別の質問。
    public let category: Question
    /// flag 名ごとの質問。
    public let flags: [String: Question]
    /// 深刻度の質問。
    public let severity: Severity

    public init(
        threshold: Double,
        attentionFlags: [String],
        category: Question,
        flags: [String: Question],
        severity: Severity
    ) {
        self.threshold = threshold
        self.attentionFlags = attentionFlags
        self.category = category
        self.flags = flags
        self.severity = severity
    }

    enum CodingKeys: String, CodingKey {
        case threshold
        case attentionFlags = "attention_flags"
        case category
        case flags
        case severity
    }

    /// castle の jev-check skill が Codex と共有する検索パス (`~/.agents/skills`) 上の質問定義。
    /// castle が未インストールの環境 (iOS・CI) ではファイルが無く、分類は利用不可になる。
    public static var defaultFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".agents/skills/jev-check/assets/rules/review-triage.json")
    }

    /// 環境変数 MAILER_JEV_RULES_PATH があればそのファイル、無ければ defaultFileURL を読み込む。
    /// ファイルが無ければ nil (分類は利用不可)。ファイルはあるが形式が不正なら投げる。
    public static func load() throws -> InquiryRuleDefinition? {
        let environment = ProcessInfo.processInfo.environment
        let fileURL: URL
        if let override = environment["MAILER_JEV_RULES_PATH"], !override.isEmpty {
            fileURL = URL(fileURLWithPath: override)
        } else {
            fileURL = defaultFileURL
        }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        return try JSONDecoder().decode(InquiryRuleDefinition.self, from: Data(contentsOf: fileURL))
    }
}
