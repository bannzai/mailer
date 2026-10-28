import Foundation

/// 通知枠 (フィルタルール) の合致条件。指定したフィールドすべてを満たすメールが枠に属する (AND)。
/// フィールドをすべて nil にした条件はすべてのメールに合致する (受け皿の枠として使う)。
public struct NotificationRuleCondition: Codable, Sendable, Equatable {
    /// 差出人アドレス (From ヘッダから取り出したアドレスと大文字小文字を無視して完全一致)。
    public var fromAddress: String?
    /// 差出人ドメイン (From ヘッダのアドレスの @ 以降と大文字小文字を無視して完全一致)。
    public var fromDomain: String?
    /// 件名に含まれる文字列 (大文字小文字を無視した部分一致)。
    public var subjectContains: String?
    /// メールが持っている必要があるラベル ID (すべて含む必要がある)。
    public var labelIds: [String]?
    /// Jev の判定結果に対する条件。判定が無い (API 不達・未判定) メールと不確実帯の判定は合致しない。
    public var classification: InquiryClassificationCondition?

    /// 全フィールド nil (すべてのメールに合致) を既定にする memberwise init (自動生成は internal のため public で書く)。
    public init(
        fromAddress: String? = nil,
        fromDomain: String? = nil,
        subjectContains: String? = nil,
        labelIds: [String]? = nil,
        classification: InquiryClassificationCondition? = nil
    ) {
        self.fromAddress = fromAddress
        self.fromDomain = fromDomain
        self.subjectContains = subjectContains
        self.labelIds = labelIds
        self.classification = classification
    }

    /// メールがこの条件に合致するか。From ヘッダが無い・アドレスを取り出せないメールは fromAddress / fromDomain の条件に合致しない。
    /// classification を要求する条件は、判定結果が渡されない (nil) メールに合致しない。
    public func matches(message: GmailMessage, classification result: InquiryClassification? = nil) -> Bool {
        if let classification {
            guard classification.matches(classification: result) else {
                return false
            }
        }
        if let fromAddress {
            guard let header = message.from,
                let address = EmailAddress.extract(fromHeader: header),
                address.caseInsensitiveCompare(fromAddress) == .orderedSame
            else {
                return false
            }
        }
        if let fromDomain {
            guard let header = message.from,
                let address = EmailAddress.extract(fromHeader: header),
                let domain = EmailAddress.domain(of: address),
                domain.caseInsensitiveCompare(fromDomain) == .orderedSame
            else {
                return false
            }
        }
        if let subjectContains {
            guard let subject = message.subject,
                subject.range(of: subjectContains, options: .caseInsensitive) != nil
            else {
                return false
            }
        }
        if let labelIds {
            guard labelIds.allSatisfy({ message.labelIds?.contains($0) == true }) else {
                return false
            }
        }
        return true
    }
}

/// 通知枠に属するメールをいつ通知するか。
public enum NotificationPolicy: Codable, Sendable, Equatable {
    /// 新着のたびに通知する。
    case immediate
    /// interval (秒) ごとにまとめて通知する。
    case batch(interval: TimeInterval)
    /// 通知しない。
    case silent
}

/// 通知枠。名前を識別子とし、条件と通知ポリシーを持つ。
public struct NotificationRule: Codable, Sendable, Equatable, Identifiable {
    /// 枠の名前。枠の識別子として使う。
    public var name: String
    /// この枠に属するメールの条件。
    public var condition: NotificationRuleCondition
    /// この枠に属するメールをいつ通知するか。
    public var policy: NotificationPolicy

    /// Identifiable 用の識別子。名前をそのまま使う。
    public var id: String { name }

    /// モジュール外 (CLI・テスト) から組み立てるための memberwise init (自動生成は internal のため)。
    public init(name: String, condition: NotificationRuleCondition, policy: NotificationPolicy) {
        self.name = name
        self.condition = condition
        self.policy = policy
    }
}

extension Array where Element == NotificationRule {
    /// メールが属する枠。先頭から評価して最初に合致した枠を返し、どれにも合致しなければ nil。
    public func firstMatching(message: GmailMessage, classification: InquiryClassification? = nil) -> NotificationRule?
    {
        first { $0.condition.matches(message: message, classification: classification) }
    }
}

/// Jev の判定結果に対する条件。列挙した種別・flag・深刻度のいずれかが採用帯で当たれば合致する (OR)。
/// issue #28 の例「深刻度 high または unusable_now / refund_request が閾値以上なら即時通知」を 1 つの枠で表せるようにするため。
/// AND で絞りたい時は、差出人・件名などの他のフィールドと組み合わせる。
public struct InquiryClassificationCondition: Codable, Sendable, Equatable {
    /// 合致させる種別の名前 (質問定義の category の選択肢名)。種別の確信度が採用帯の時だけ当たる。
    public var categories: [String]?
    /// 合致させる flag の名前。その flag の確率が採用帯の時だけ当たる。
    public var flags: [String]?
    /// 合致させる深刻度の段階名 (質問定義の severity.levels)。深刻度の確信度が採用帯の時だけ当たる。
    public var severities: [String]?

    /// 全フィールド nil を既定にする memberwise init (自動生成は internal のため public で書く)。
    public init(categories: [String]? = nil, flags: [String]? = nil, severities: [String]? = nil) {
        self.categories = categories
        self.flags = flags
        self.severities = severities
    }

    /// 判定結果がこの条件に合致するか。判定が無い (nil) 時と、該当するものが不確実帯・却下帯の時は合致しない。
    public func matches(classification: InquiryClassification?) -> Bool {
        guard let classification else {
            return false
        }
        if let categories, categories.contains(classification.category),
            InquiryClassificationBand(probability: classification.categoryConfidence) == .adopted
        {
            return true
        }
        // 判定結果に無い flag (質問定義に無い名前を条件に書いた時) は却下帯の 0 として扱い、合致させない。
        if let flags,
            flags.contains(where: { InquiryClassificationBand(probability: classification.flags[$0] ?? 0) == .adopted })
        {
            return true
        }
        if let severities, severities.contains(classification.severity),
            InquiryClassificationBand(probability: classification.severityConfidence) == .adopted
        {
            return true
        }
        return false
    }
}
