import Foundation

/// 枠ごとの通知の進行状態。永続化して次回の判定に引き継ぐ。
public struct NotificationRuleState: Codable, Sendable, Equatable {
    /// この枠で最後に通知した時刻。一度も通知していなければ nil。
    public var lastNotifiedAt: Date?
    /// 次回バッチまで保留しているメール ID (受信順)。
    public var pendingMessageIds: [String]

    public init(lastNotifiedAt: Date? = nil, pendingMessageIds: [String] = []) {
        self.lastNotifiedAt = lastNotifiedAt
        self.pendingMessageIds = pendingMessageIds
    }
}

/// 今すぐ通知する 1 まとまり。枠ごとに 1 件、枠に属さないメールは ruleName nil の 1 件にまとめる。
public struct NotificationDelivery: Sendable, Equatable {
    /// 属する枠の名前。どの枠にも合致しなかったメールは nil。
    public let ruleName: String?
    /// 通知するメール ID (保留していたものが先、新着が後)。
    public let messageIds: [String]

    public init(ruleName: String?, messageIds: [String]) {
        self.ruleName = ruleName
        self.messageIds = messageIds
    }
}

/// 判定結果。
public struct NotificationDecision: Sendable, Equatable {
    /// 今すぐ通知するまとまり。rules の並び順、最後に枠なし (ruleName nil) の順。空のまとまりは含めない。
    public let deliveries: [NotificationDelivery]
    /// 判定後の枠ごとの状態。永続化する値そのもの (入力 states のうち rules に無い枠の状態もそのまま残す)。
    public let states: [String: NotificationRuleState]

    public init(deliveries: [NotificationDelivery], states: [String: NotificationRuleState]) {
        self.deliveries = deliveries
        self.states = states
    }

    /// 次回バッチまで保留するメール ID (枠名 -> ID 列)。保留が無い枠は含めない。states から導出する。
    public var deferredMessageIds: [String: [String]] {
        states.compactMapValues { $0.pendingMessageIds.isEmpty ? nil : $0.pendingMessageIds }
    }

    /// 今すぐ通知するメール ID をすべて平坦にしたもの。
    public var immediateMessageIds: [String] {
        deliveries.flatMap(\.messageIds)
    }
}

/// 新着メール集合と枠定義から「今すぐ通知するメール / 次回バッチまで保留するメール」を決める。
/// OS 依存の通知配信とは分離し、どのプラットフォームでも同じ結果になる純粋関数。
public enum NotificationEngine {
    /// どの枠にも合致しないメールに適用するポリシー。
    /// 枠を 1 つも設定していない状態で通知が届かなくなると、Gmail 公式アプリの通知を切って本アプリに一本化する運用 (issue #10) が成立しないため即時通知にする。
    public static let defaultPolicy: NotificationPolicy = .immediate

    /// - Parameters:
    ///   - messages: 新着メール (受信順)。
    ///   - rules: 枠定義 (先頭から評価し最初に合致した枠に属する)。
    ///   - states: 前回判定後の枠ごとの状態。
    ///   - now: 判定時刻。
    public static func decide(
        messages: [GmailMessage],
        rules: [NotificationRule],
        states: [String: NotificationRuleState],
        now: Date
    ) -> NotificationDecision {
        var arrivedIdsByRuleName: [String: [String]] = [:]
        var unmatchedMessageIds: [String] = []
        for message in messages {
            if let rule = rules.firstMatching(message: message) {
                arrivedIdsByRuleName[rule.name, default: []].append(message.id)
            } else {
                unmatchedMessageIds.append(message.id)
            }
        }

        var deliveries: [NotificationDelivery] = []
        var updatedStates = states
        // 新着が無い枠も評価する。保留中メールの期限到来を拾うため。
        for rule in rules {
            var state = states[rule.name] ?? NotificationRuleState()
            let arrivedIds = arrivedIdsByRuleName[rule.name] ?? []
            switch rule.policy {
            case .immediate:
                guard !arrivedIds.isEmpty else { continue }
                deliveries.append(NotificationDelivery(ruleName: rule.name, messageIds: arrivedIds))
                state.lastNotifiedAt = now
                state.pendingMessageIds = []
            case .batch(let interval):
                var pendingMessageIds = state.pendingMessageIds
                for arrivedId in arrivedIds where !pendingMessageIds.contains(arrivedId) {
                    pendingMessageIds.append(arrivedId)
                }
                guard !pendingMessageIds.isEmpty else { continue }
                // lastNotifiedAt == nil のうちは即時に出す。最初の 1 通で時計を始め、その後は interval ごとにまとめるため。
                if let lastNotifiedAt = state.lastNotifiedAt, now.timeIntervalSince(lastNotifiedAt) < interval {
                    state.pendingMessageIds = pendingMessageIds
                } else {
                    deliveries.append(NotificationDelivery(ruleName: rule.name, messageIds: pendingMessageIds))
                    state.lastNotifiedAt = now
                    state.pendingMessageIds = []
                }
            case .silent:
                continue
            }
            updatedStates[rule.name] = state
        }

        // 枠なしのメールは状態を持たないため、defaultPolicy が即時通知の時だけ通知できる。
        if !unmatchedMessageIds.isEmpty, defaultPolicy == .immediate {
            deliveries.append(NotificationDelivery(ruleName: nil, messageIds: unmatchedMessageIds))
        }
        return NotificationDecision(deliveries: deliveries, states: updatedStates)
    }
}
