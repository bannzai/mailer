import ArgumentParser
import Foundation
import MailerCore

struct ArchiveCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "archive",
        abstract: "メールをアーカイブする (INBOX ラベルを外す)"
    )

    @OptionGroup var accountOptions: AccountOptions

    @Argument(help: "アーカイブする message id (複数指定可)")
    var ids: [String]

    func run() async throws {
        let client = try CLIContext.gmailClient(explicitAccount: accountOptions.account)
        try await client.batchModify(ids: ids, removeLabelIds: ["INBOX"])
        print("\(ids.count)件をアーカイブしました。")
    }
}
