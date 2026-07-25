import ArgumentParser
import Foundation
import MailerCore

struct InboxCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "inbox",
        abstract: "受信トレイの一覧を表示する"
    )

    @OptionGroup var accountOptions: AccountOptions

    @Option(name: .long, help: "取得する最大件数")
    var max: Int = 30

    func run() async throws {
        let client = try CLIContext.gmailClient(explicitAccount: accountOptions.account)
        let list = try await client.listMessages(labelIds: ["INBOX"], maxResults: max)
        let refs = list.messages ?? []
        guard !refs.isEmpty else {
            print("受信トレイは空です。")
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
        for message in messages {
            print(message.summaryLine)
        }
    }
}
