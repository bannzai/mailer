import ArgumentParser
import Foundation
import MailerCore

struct QuickLabelCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "quicklabel",
        abstract: "ラベル即分け: ラベル作成 + フィルタ作成 + 既存一致メールの移動を一括で行う"
    )

    @OptionGroup var accountOptions: AccountOptions

    @Argument(help: "振り分け先のラベル名")
    var name: String

    @Option(name: .long, help: "対象メールの message id。From ヘッダの差出人アドレスを条件にする")
    var message: String?

    @Option(name: .long, help: "差出人アドレスを条件にする (例: news@example.com)")
    var from: String?

    @Option(name: .long, help: "差出人ドメインを条件にする (例: example.com)")
    var domain: String?

    @Option(name: .long, help: "件名に含まれる文字列を条件にする")
    var subject: String?

    func validate() throws {
        let conditions = [message, from, domain, subject].compactMap(\.self)
        guard conditions.count == 1 else {
            throw ValidationError("--message / --from / --domain / --subject のいずれか1つを指定してください。")
        }
    }

    func run() async throws {
        let client = try CLIContext.gmailClient(explicitAccount: accountOptions.account)
        let condition = try await resolveCondition(client: client)
        let result = try await client.quickLabel(condition: condition, labelName: name)

        print("ラベル「\(result.label.name)」(\(result.label.id))")
        print(result.filterCreated ? "フィルタを作成しました。" : "同等のフィルタが既に存在するため作成をスキップしました。")
        print("既存の一致メール \(result.movedMessageCount)件にラベル付与 + INBOX 除去を適用しました。")
    }

    private func resolveCondition(client: GmailClient) async throws -> QuickLabelCondition {
        if let from {
            return .fromAddress(from)
        }
        if let domain {
            return .fromDomain(domain)
        }
        if let subject {
            return .subjectContains(subject)
        }
        guard let message else {
            throw ValidationError("条件が指定されていません。")
        }
        let fetched = try await client.getMessage(id: message, format: .metadata(headers: ["From"]))
        guard let fromHeader = fetched.from, let address = EmailAddress.extract(fromHeader: fromHeader) else {
            throw ValidationError("message \(message) の From ヘッダから差出人アドレスを取得できませんでした。")
        }
        return .fromAddress(address)
    }
}
