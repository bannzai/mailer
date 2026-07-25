import ArgumentParser
import Foundation
import MailerCore

struct LabelCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "label",
        abstract: "メールにラベルを付与する (ラベルが無ければ作成する)"
    )

    @OptionGroup var accountOptions: AccountOptions

    @Argument(help: "付与するラベル名")
    var name: String

    @Argument(help: "対象の message id (複数指定可)")
    var ids: [String]

    func run() async throws {
        let client = try CLIContext.gmailClient(explicitAccount: accountOptions.account)
        let label = try await client.findOrCreateLabel(name: name)
        try await client.batchModify(ids: ids, addLabelIds: [label.id])
        print("\(ids.count)件にラベル「\(label.name)」を付与しました。")
    }
}
