import ArgumentParser
import Foundation
import MailerCore

struct AccountsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "accounts",
        abstract: "アカウントの一覧・追加・削除・既定切り替え",
        subcommands: [List.self, Add.self, Remove.self, SetDefault.self],
        defaultSubcommand: List.self
    )

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "list", abstract: "登録済みアカウントを一覧する")

        func run() throws {
            let list = try AccountStore().load()
            guard !list.accounts.isEmpty else {
                print("アカウントが登録されていません。`mailer accounts add` で追加してください。")
                return
            }
            for record in list.accounts {
                let marker = record.email == list.defaultAccount ? "*" : " "
                print("\(marker) \(record.email)")
            }
        }
    }

    struct Add: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "add",
            abstract: "ブラウザで Google 認可フローを実行してアカウントを追加する"
        )

        @Option(name: .long, help: "Google の認可画面に事前入力するメールアドレス")
        var loginHint: String?

        func run() async throws {
            let manager = try CLIContext.accountManager()
            print("ブラウザで Google の認可画面を開きます...")
            let record = try await manager.addAccountViaLoopback(loginHint: loginHint) { url in
                CLIContext.openInBrowser(url)
                print("開かない場合は次の URL を手動で開いてください:")
                print(url.absoluteString)
            }
            print("アカウント \(record.email) を追加しました。")
        }
    }

    struct Remove: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "remove",
            abstract: "アカウントを削除してトークンを失効させる"
        )

        @Argument(help: "削除するアカウントのメールアドレス")
        var email: String

        func run() async throws {
            let manager = try CLIContext.accountManager()
            try await manager.removeAccount(email: email)
            print("アカウント \(email) を削除しました。")
        }
    }

    struct SetDefault: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "default",
            abstract: "既定アカウントを切り替える"
        )

        @Argument(help: "既定にするアカウントのメールアドレス")
        var email: String

        func run() throws {
            try AccountStore().setDefault(email: email)
            print("既定アカウントを \(email) にしました。")
        }
    }
}
