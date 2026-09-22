import ArgumentParser
import Foundation
import MailerCore

/// 受信処理の分類ステップを CLI から実行する。未判定のメールだけ Jev に送り、結果を保存して通知枠との対応を表示する。
struct ClassifyCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "classify",
        abstract: "受信トレイのメールを Jev で分類し、結果を保存して通知枠との対応を表示する"
    )

    @OptionGroup var accountOptions: AccountOptions

    /// 既定は inbox コマンドと同じ 30 件 (受信トレイの一覧で見える範囲を分類する)。
    @Option(name: .long, help: "対象にする受信トレイの最大件数")
    var max: Int = 30

    @Option(
        name: .long,
        help: "対象を絞る Gmail の検索クエリ (例: to:support@example.com)。Jev に送ってよいのは問い合わせメールの本文なので、問い合わせが届く宛先や件名で絞る"
    )
    var query: String?

    func run() async throws {
        let client = try CLIContext.gmailClient(explicitAccount: accountOptions.account)
        let refs = try await client.listMessages(query: query, labelIds: ["INBOX"], maxResults: max).messages ?? []
        guard !refs.isEmpty else {
            print("対象のメールがありません。")
            return
        }
        let messages = try await withThrowingTaskGroup(of: (Int, GmailMessage).self) { group in
            for (index, ref) in refs.enumerated() {
                group.addTask {
                    (index, try await client.getMessage(id: ref.id, format: .metadata(headers: ["From", "Subject"])))
                }
            }
            var results: [(Int, GmailMessage)] = []
            for try await result in group {
                results.append(result)
            }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }

        let run = await InquiryClassificationPipeline(
            gmail: client,
            classifier: try CLIContext.inquiryClassifier(),
            store: InquiryClassificationStore()
        ).classify(messages: messages)
        let rules = try NotificationRuleStore().load()
        for message in messages {
            let classification = run.classifications[message.id]
            let ruleName = rules.firstMatching(message: message, classification: classification)?.name ?? "枠なし"
            print("\(message.summaryLine)  \(classificationSummary(classification: classification))  枠=\(ruleName)")
        }
        print(
            "判定: 新規 \(run.classifiedMessageIds.count) 件 / 保存済み \(run.classifications.count - run.classifiedMessageIds.count) 件 / 判定なし \(run.unavailableMessageIds.count) 件"
        )
        if let reason = run.unavailableReason {
            print("判定なしの理由: \(reason)")
        }
    }
}

/// 一覧に出す判定結果の要約 ("種別 (確信度)  深刻度 (確信度)  flags=採用帯の flag")。判定が無ければ「分類なし」。
private func classificationSummary(classification: InquiryClassification?) -> String {
    guard let classification else {
        return "分類なし"
    }
    let flags = classification.adoptedFlags.isEmpty ? "-" : classification.adoptedFlags.joined(separator: ",")
    return
        "\(classification.category) (\(classification.categoryConfidence))  \(classification.severity) (\(classification.severityConfidence))  flags=\(flags)"
}
