import Foundation

/// Jev (TypeSafe) の API キーの置き場所。環境変数または設定ファイル (typesafe.json) から読み込む。
/// キーは CLI / macOS の設定ディレクトリにだけ置き、iOS アプリには配布しない (iOS では load が nil を返し分類は利用不可になる)。
public struct InquiryClassifierConfiguration: Codable, Sendable, Equatable {
    /// TypeSafe の API キー (https://console.typesafe.ai/settings/keys で発行)。
    public var apiKey: String

    public init(apiKey: String) {
        self.apiKey = apiKey
    }

    /// 環境変数 TYPESAFE_API_KEY (公式 SDK・castle のスクリプトと同じ名前) を優先し、
    /// 無ければ configDirectory/typesafe.json から読み込む。どちらも無ければ nil (分類は利用不可)。
    public static func load(configDirectory: URL = MailerPaths.configDirectory) throws
        -> InquiryClassifierConfiguration?
    {
        if let apiKey = ProcessInfo.processInfo.environment["TYPESAFE_API_KEY"], !apiKey.isEmpty {
            return InquiryClassifierConfiguration(apiKey: apiKey)
        }
        let fileURL = configDirectory.appendingPathComponent("typesafe.json")
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        return try JSONDecoder().decode(InquiryClassifierConfiguration.self, from: Data(contentsOf: fileURL))
    }
}

/// Jev の API 呼び出しで起きるエラー。呼び出し側は分類できなかったものとして扱い、受信処理を止めない。
public enum InquiryClassifierError: Error, LocalizedError, Equatable {
    /// HTTP エラー (再試行しても 200 にならなかったものを含む)。
    case httpStatus(Int)
    /// 応答に要求した質問の回答が欠けている。
    case missingAnswer(String)
    /// 深刻度のスコアが levels の範囲外。
    case severityOutOfRange(Double)

    public var errorDescription: String? {
        switch self {
        case .httpStatus(let statusCode):
            return "Jev API がエラーを返しました (HTTP \(statusCode))"
        case .missingAnswer(let question):
            return "Jev API の応答に \(question) の回答がありません"
        case .severityOutOfRange(let score):
            return "Jev API の深刻度スコア \(score) が段階の範囲外です"
        }
    }
}

/// 問い合わせメールの本文 1 件を Jev に送り、判定結果を返す。1 件 = 1 リクエスト。
/// 読み取り専用の API なので同じ本文を何度送っても外部の状態は変わらない (冪等)。
public struct InquiryClassifier: Sendable {
    /// TypeSafe の評価 API。
    public static let endpoint = URL(string: "https://api.typesafe.ai/v1/systemone")!
    /// 判定モデル。alias (jev-latest) は新版で同じ入力への答えが変わり得るため、閾値を調整したバージョンに固定する。
    public static let model = "jev-1.13.0"
    /// 1 リクエストの最大待ち時間。castle の実測 (2026-09-19、58 リクエスト) では通常 1 秒未満で返り、
    /// 60 秒のタイムアウトが 2 回起きどちらも再送で 0.6 秒で返った ( https://github.com/bannzai/castle/issues/1142 )。
    /// 受信処理でメール件数分を直列に待つため、通常応答の 20 倍以上を確保しつつ 60 秒より短くする。
    public static let defaultTimeout: TimeInterval = 20

    /// TypeSafe の API キー (Authorization: Bearer に載せる)。
    let apiKey: String
    /// Jev に投げる質問定義 (種別の選択肢・flag・深刻度の段階)。
    let rules: InquiryRuleDefinition
    /// HTTP の送信経路。テストでは MockTransport を注入する。
    let transport: HTTPTransport
    /// HTTP 429 (rate limit) / 529 (overloaded) の再試行の待機秒数。要素数が最大再試行回数になる。
    /// 公式ドキュメントの指数バックオフ (2 秒・4 秒。https://docs.typesafe.ai/api.md「Handling rate limits」) に合わせる。テストでは 0 を注入する。
    let retryDelays: [TimeInterval]
    /// 1 リクエストの最大待ち時間 (秒)。
    let timeout: TimeInterval

    /// retryDelays と timeout の既定値は上の定数の根拠に従う。テストでは 0 と短い timeout を注入する。
    public init(
        apiKey: String,
        rules: InquiryRuleDefinition,
        transport: HTTPTransport = URLSessionTransport(),
        retryDelays: [TimeInterval] = [2, 4],
        timeout: TimeInterval = Self.defaultTimeout
    ) {
        self.apiKey = apiKey
        self.rules = rules
        self.transport = transport
        self.retryDelays = retryDelays
        self.timeout = timeout
    }

    /// 本文を分類する。タイムアウトは 1 回だけ再送する (castle の実測で再送が有効だったため)。
    public func classify(text: String, now: Date = Date()) async throws -> InquiryClassification {
        var request = URLRequest(url: Self.endpoint, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try requestBody(text: text)

        var retryIndex = 0
        var didRetryTimeout = false
        while true {
            let data: Data
            let response: HTTPURLResponse
            do {
                (data, response) = try await transport.send(request)
            } catch let error as URLError where error.code == .timedOut && !didRetryTimeout {
                didRetryTimeout = true
                continue
            }
            switch response.statusCode {
            case 200..<300:
                return try Self.parse(data: data, rules: rules, now: now)
            case 429, 529:
                guard retryIndex < retryDelays.count else {
                    throw InquiryClassifierError.httpStatus(response.statusCode)
                }
                let delay = retryDelays[retryIndex]
                retryIndex += 1
                if delay > 0 {
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            default:
                throw InquiryClassifierError.httpStatus(response.statusCode)
            }
        }
    }

    /// castle の classify-review.sh が組み立てるリクエストと同じ形 (state.review に本文、questions に種別・flag・深刻度)。
    func requestBody(text: String) throws -> Data {
        var questions: [String: JevQuestion] = [
            "category": .choice(instructions: rules.category.instructions, criteria: rules.category.criteria),
            "severity": .score(instructions: rules.severity.instructions, criteria: rules.severity.levels),
        ]
        for (name, flag) in rules.flags {
            questions[name] = .noul(instructions: flag.instructions, criteria: flag.criteria)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(JevRequest(state: ["review": text], questions: questions, model: Self.model))
    }

    /// 応答の JSON を判定結果にする。category / severity / 質問定義にある全 flag の回答が無ければ missingAnswer、
    /// 深刻度のスコアを丸めた添字が levels の範囲外なら severityOutOfRange を投げる。classifiedAt には now を入れる。
    static func parse(data: Data, rules: InquiryRuleDefinition, now: Date) throws -> InquiryClassification {
        let response = try JSONDecoder().decode(JevResponse.self, from: data)
        guard let category = response.answers["category"], let choice = category.choice,
            let categoryConfidence = category.confidence
        else {
            throw InquiryClassifierError.missingAnswer("category")
        }
        guard let severity = response.answers["severity"], let score = severity.score,
            let severityConfidence = severity.confidence
        else {
            throw InquiryClassifierError.missingAnswer("severity")
        }
        let levelIndex = Int(score.rounded())
        guard rules.severity.levels.indices.contains(levelIndex) else {
            throw InquiryClassifierError.severityOutOfRange(score)
        }
        var flags: [String: Double] = [:]
        for name in rules.flags.keys {
            guard let probability = response.answers[name]?.noul else {
                throw InquiryClassifierError.missingAnswer(name)
            }
            flags[name] = probability
        }
        return InquiryClassification(
            category: choice,
            categoryConfidence: categoryConfidence,
            severity: rules.severity.levels[levelIndex],
            severityScore: score,
            severityConfidence: severityConfidence,
            flags: flags,
            model: response.model,
            classifiedAt: now
        )
    }
}

/// POST /v1/systemone のリクエスト本体。
struct JevRequest: Encodable {
    /// 判定対象のテキスト (キー review に本文を入れる。質問の instructions が `review` を参照する)。
    let state: [String: String]
    /// 質問名 -> 質問定義。
    let questions: [String: JevQuestion]
    /// 判定モデル ID。
    let model: String
}

/// 質問の種類ごとに criteria の形が違う (choice / noul は選択肢名 -> 基準、score は段階名の配列)。
enum JevQuestion: Encodable {
    case choice(instructions: String, criteria: [String: String])
    case noul(instructions: String, criteria: [String: String])
    case score(instructions: String, criteria: [String])

    /// API のリクエストで質問 1 件が持つキー。
    enum CodingKeys: String, CodingKey {
        case type
        case instructions
        case criteria
    }

    /// 種類ごとの criteria の形を保ったまま type / instructions / criteria の 3 キーに書き出す。
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .choice(let instructions, let criteria):
            try container.encode("choice", forKey: .type)
            try container.encode(instructions, forKey: .instructions)
            try container.encode(criteria, forKey: .criteria)
        case .noul(let instructions, let criteria):
            try container.encode("noul", forKey: .type)
            try container.encode(instructions, forKey: .instructions)
            try container.encode(criteria, forKey: .criteria)
        case .score(let instructions, let criteria):
            try container.encode("score", forKey: .type)
            try container.encode(instructions, forKey: .instructions)
            try container.encode(criteria, forKey: .criteria)
        }
    }
}

/// POST /v1/systemone の応答のうち mailer が使う部分。
struct JevResponse: Decodable {
    /// 実際に判定したモデル ID。
    let model: String
    /// 質問名 -> 回答。
    let answers: [String: JevAnswer]
}

/// 質問 1 件の回答。type によって入るフィールドが違う (choice: choice + confidence、noul: noul、score: score + confidence)。
struct JevAnswer: Decodable {
    /// 質問の種類 (choice / noul / score)。
    let type: String
    /// choice の選ばれた選択肢名。
    let choice: String?
    /// choice / score の確信度 (0〜1)。
    let confidence: Double?
    /// noul の該当確率 (0〜1)。
    let noul: Double?
    /// score の実数値 (段階の添字に対応)。
    let score: Double?
}
