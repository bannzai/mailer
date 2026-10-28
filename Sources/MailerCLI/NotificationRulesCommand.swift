import ArgumentParser
import Foundation
import MailerCore

/// 通知枠 (フィルタルール) を CLI から管理する。枠定義は NotificationRuleStore の notification-rules.json に保存する。
struct NotificationRulesCommand: ParsableCommand {
    /// コマンド名・説明・サブコマンド (既定は list)。
    static let configuration = CommandConfiguration(
        commandName: "notification-rules",
        abstract: "通知枠 (フィルタルール) の一覧・追加・削除",
        subcommands: [List.self, Add.self, Remove.self],
        defaultSubcommand: List.self
    )

    /// 登録済みの通知枠を評価順 (保存した並び) に 1 行ずつ表示する。
    struct List: ParsableCommand {
        /// サブコマンド名と説明。
        static let configuration = CommandConfiguration(commandName: "list", abstract: "登録済みの通知枠を一覧する")

        /// 枠を読み込んで 1 行ずつ表示する。無ければ追加方法を案内する。
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
        /// サブコマンド名と説明。
        static let configuration = CommandConfiguration(commandName: "add", abstract: "通知枠を追加する (同名なら置き換え)")

        /// 枠の名前 (識別子)。
        @Argument(help: "通知枠の名前 (識別子)")
        var name: String

        /// 条件: 差出人アドレスの完全一致。
        @Option(name: .long, help: "差出人アドレスを条件にする (例: news@example.com)")
        var from: String?

        /// 条件: 差出人ドメインの完全一致。
        @Option(name: .long, help: "差出人ドメインを条件にする (例: example.com)")
        var domain: String?

        /// 条件: 件名の部分一致。
        @Option(name: .long, help: "件名に含まれる文字列を条件にする")
        var subject: String?

        /// 条件: すべて持っている必要があるラベル ID。
        @Option(name: .long, help: "メールが持っている必要があるラベル ID (複数指定可)")
        var label: [String] = []

        /// 条件: Jev の判定の種別 (いずれかに当たれば合致)。
        @Option(
            name: .long,
            help: "Jev の判定の種別を条件にする (複数指定可。bug / billing 等、質問定義 review-triage.json の category の名前)"
        )
        var category: [String] = []

        /// 条件: Jev の判定の flag (いずれかが採用帯なら合致)。
        @Option(
            name: .long,
            help: "Jev の判定の flag を条件にする (複数指定可。unusable_now / refund_request 等、質問定義の flags の名前)"
        )
        var flag: [String] = []

        /// 条件: Jev の判定の深刻度の段階名 (いずれかに当たれば合致)。
        @Option(name: .long, help: "Jev の判定の深刻度を条件にする (複数指定可。none / low / medium / high)")
        var severity: [String] = []

        /// ポリシー: 新着のたびに通知する。
        @Flag(name: .long, help: "新着のたびに通知する")
        var immediate = false

        /// ポリシー: 指定した時間ごとにまとめて通知する。
        @Option(name: .long, help: "指定した時間ごとにまとめて通知する")
        var batchHours: Double?

        /// ポリシー: 通知しない。
        @Flag(name: .long, help: "通知しない")
        var silent = false

        /// バッチ間隔の上限 (時間)。1 年を超える間隔は通知しない枠と変わらず、巨大値は一覧の時間表記で Int に収まらないため。
        static let maxBatchHours: Double = 24 * 365

        /// 条件を 1 つ以上、ポリシーをちょうど 1 つ指定していることと、条件の値が空白だけでないこと、
        /// バッチ間隔が 0 より大きく上限以下であることを検査する。
        func validate() throws {
            guard from != nil || domain != nil || subject != nil || !label.isEmpty || classificationCondition != nil
            else {
                throw ValidationError(
                    "--from / --domain / --subject / --label / --category / --flag / --severity のいずれか1つ以上を指定してください。"
                )
            }
            // 空のシェル変数が --subject '' のように渡ると、空文字の部分一致で全メールに合致する枠が保存されるため拒否する。
            let conditionValues = [from, domain, subject].compactMap(\.self) + label + category + flag + severity
            if conditionValues.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                throw ValidationError("条件の値に空文字・空白だけの文字列は指定できません。")
            }
            guard [immediate, batchHours != nil, silent].filter(\.self).count == 1 else {
                throw ValidationError("--immediate / --batch-hours / --silent のいずれか1つを指定してください。")
            }
            if let batchHours, !(batchHours > 0 && batchHours <= Self.maxBatchHours) {
                throw ValidationError(
                    "--batch-hours には 0 より大きく \(Int(Self.maxBatchHours)) 以下の値を指定してください。"
                )
            }
        }

        /// 枠を保存して結果を表示する。
        func run() throws {
            try NotificationRuleStore().add(
                rule: NotificationRule(
                    name: name,
                    condition: NotificationRuleCondition(
                        fromAddress: from,
                        fromDomain: domain,
                        subjectContains: subject,
                        labelIds: label.isEmpty ? nil : label,
                        classification: classificationCondition
                    ),
                    policy: policy
                )
            )
            print("通知枠「\(name)」を保存しました。")
        }

        /// --category / --flag / --severity のどれかがあれば分類条件 (列挙したいずれかに当たれば合致)。
        private var classificationCondition: InquiryClassificationCondition? {
            guard !category.isEmpty || !flag.isEmpty || !severity.isEmpty else {
                return nil
            }
            return InquiryClassificationCondition(
                categories: category.isEmpty ? nil : category,
                flags: flag.isEmpty ? nil : flag,
                severities: severity.isEmpty ? nil : severity
            )
        }

        /// --immediate / --batch-hours / --silent から決まる通知ポリシー (validate でちょうど 1 つを保証済み)。
        private var policy: NotificationPolicy {
            if let batchHours {
                return .batch(interval: batchHours * 3600)
            }
            return silent ? .silent : .immediate
        }
    }

    /// 名前で指定した通知枠を削除する。無ければエラー。
    struct Remove: ParsableCommand {
        /// サブコマンド名と説明。
        static let configuration = CommandConfiguration(commandName: "remove", abstract: "通知枠を削除する")

        /// 削除する枠の名前。
        @Argument(help: "削除する通知枠の名前")
        var name: String

        /// 枠を削除して結果を表示する。
        func run() throws {
            try NotificationRuleStore().remove(name: name)
            print("通知枠「\(name)」を削除しました。")
        }
    }
}

/// 一覧に出す条件の要約 ("from:A domain:D subject:S label:L1,L2 category:C flag:F severity:S" のうち設定済みのものだけ)。
private func conditionSummary(condition: NotificationRuleCondition) -> String {
    let parts: [String?] = [
        condition.fromAddress.map { "from:\($0)" },
        condition.fromDomain.map { "domain:\($0)" },
        condition.subjectContains.map { "subject:\($0)" },
        condition.labelIds.map { "label:\($0.joined(separator: ","))" },
        condition.classification?.categories.map { "category:\($0.joined(separator: ","))" },
        condition.classification?.flags.map { "flag:\($0.joined(separator: ","))" },
        condition.classification?.severities.map { "severity:\($0.joined(separator: ","))" },
    ]
    return parts.compactMap(\.self).joined(separator: " ")
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
/// 手で編集したファイルの巨大値でも落ちないよう Int に変換せず、%g (有効 6 桁) で表記する。
private func batchHoursText(interval: TimeInterval) -> String {
    String(format: "%g", interval / 3600)
}
