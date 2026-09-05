import ArgumentParser
import Foundation
import MailerCore

struct NotificationRulesCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "notification-rules",
        abstract: "通知枠 (フィルタルール) の一覧・追加・削除",
        subcommands: [List.self, Add.self, Remove.self],
        defaultSubcommand: List.self
    )

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "list", abstract: "登録済みの通知枠を一覧する")

        func run() throws {
            let rules = try NotificationRuleStore().load()
            guard !rules.isEmpty else {
                print("通知枠が登録されていません。`mailer notification-rules add` で追加してください。")
                return
            }
            for rule in rules {
                print(
                    "\(rule.name)  \(conditionSummary(condition: rule.condition))  \(policySummary(policy: rule.policy))"
                )
            }
        }
    }

    /// 通知枠を追加する。同名の枠が既にあれば置き換える (冪等)。
    struct Add: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "add", abstract: "通知枠を追加する (同名なら置き換え)")

        @Argument(help: "通知枠の名前 (識別子)")
        var name: String

        @Option(name: .long, help: "差出人アドレスを条件にする (例: news@example.com)")
        var from: String?

        @Option(name: .long, help: "差出人ドメインを条件にする (例: example.com)")
        var domain: String?

        @Option(name: .long, help: "件名に含まれる文字列を条件にする")
        var subject: String?

        @Option(name: .long, help: "メールが持っている必要があるラベル ID (複数指定可)")
        var label: [String] = []

        @Flag(name: .long, help: "新着のたびに通知する")
        var immediate = false

        @Option(name: .long, help: "指定した時間ごとにまとめて通知する")
        var batchHours: Double?

        @Flag(name: .long, help: "通知しない")
        var silent = false

        func validate() throws {
            guard from != nil || domain != nil || subject != nil || !label.isEmpty else {
                throw ValidationError("--from / --domain / --subject / --label のいずれか1つ以上を指定してください。")
            }
            guard [immediate, batchHours != nil, silent].filter(\.self).count == 1 else {
                throw ValidationError("--immediate / --batch-hours / --silent のいずれか1つを指定してください。")
            }
            if let batchHours, batchHours <= 0 {
                throw ValidationError("--batch-hours には 0 より大きい値を指定してください。")
            }
        }

        func run() throws {
            try NotificationRuleStore().add(
                NotificationRule(
                    name: name,
                    condition: NotificationRuleCondition(
                        fromAddress: from,
                        fromDomain: domain,
                        subjectContains: subject,
                        labelIds: label.isEmpty ? nil : label
                    ),
                    policy: policy
                )
            )
            print("通知枠「\(name)」を保存しました。")
        }

        private var policy: NotificationPolicy {
            if let batchHours {
                return .batch(interval: batchHours * 3600)
            }
            return silent ? .silent : .immediate
        }
    }

    struct Remove: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "remove", abstract: "通知枠を削除する")

        @Argument(help: "削除する通知枠の名前")
        var name: String

        func run() throws {
            try NotificationRuleStore().remove(name: name)
            print("通知枠「\(name)」を削除しました。")
        }
    }
}

/// 一覧に出す条件の要約 ("from:A domain:D subject:S label:L1,L2" のうち設定済みのものだけ)。
private func conditionSummary(condition: NotificationRuleCondition) -> String {
    [
        condition.fromAddress.map { "from:\($0)" },
        condition.fromDomain.map { "domain:\($0)" },
        condition.subjectContains.map { "subject:\($0)" },
        condition.labelIds.map { "label:\($0.joined(separator: ","))" },
    ]
    .compactMap(\.self)
    .joined(separator: " ")
}

/// 一覧に出すポリシーの要約。
private func policySummary(policy: NotificationPolicy) -> String {
    switch policy {
    case .immediate:
        return "即時"
    case .batch(let interval):
        return "\(batchHoursText(interval: interval))時間ごとにまとめる"
    case .silent:
        return "通知しない"
    }
}

/// バッチ間隔を時間表記にする。整数時間なら小数点を出さない。
private func batchHoursText(interval: TimeInterval) -> String {
    let hours = interval / 3600
    return hours == hours.rounded() ? String(Int(hours)) : String(hours)
}
