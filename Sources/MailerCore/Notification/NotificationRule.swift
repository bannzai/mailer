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

    public init(
        fromAddress: String? = nil,
        fromDomain: String? = nil,
        subjectContains: String? = nil,
        labelIds: [String]? = nil
    ) {
        self.fromAddress = fromAddress
        self.fromDomain = fromDomain
        self.subjectContains = subjectContains
        self.labelIds = labelIds
    }

    /// メールがこの条件に合致するか。From ヘッダが無い・アドレスを取り出せないメールは fromAddress / fromDomain の条件に合致しない。
    public func matches(message: GmailMessage) -> Bool {
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

    public var id: String { name }

    public init(name: String, condition: NotificationRuleCondition, policy: NotificationPolicy) {
        self.name = name
        self.condition = condition
        self.policy = policy
    }
}

extension Array where Element == NotificationRule {
    /// メールが属する枠。先頭から評価して最初に合致した枠を返し、どれにも合致しなければ nil。
    public func firstMatching(message: GmailMessage) -> NotificationRule? {
        first { $0.condition.matches(message: message) }
    }
}
