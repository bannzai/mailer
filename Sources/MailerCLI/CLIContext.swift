import ArgumentParser
import Foundation
import MailerCore

/// 全コマンド共通の対象アカウント指定。
struct AccountOptions: ParsableArguments {
    @Option(name: .long, help: "対象アカウントのメールアドレス。省略時は既定アカウント。")
    var account: String?
}

/// コマンド実行に必要な依存を組み立てる。
enum CLIContext {
    static func accountManager() throws -> AccountManager {
        AccountManager(configuration: try OAuthConfiguration.load())
    }

    static func gmailClient(explicitAccount: String?) throws -> GmailClient {
        let manager = try accountManager()
        let email = try AccountStore().resolveAccount(explicitAccount)
        return GmailClient(email: email, tokenProvider: manager.tokenProvider())
    }

    /// 認可 URL を既定ブラウザで開く。開けない環境では URL を表示して手動で開いてもらう。
    static func openInBrowser(_ url: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [url.absoluteString]
        do {
            try process.run()
        } catch {
            print("ブラウザを起動できませんでした。次の URL を手動で開いてください:")
            print(url.absoluteString)
        }
    }
}

extension GmailMessage {
    /// 一覧表示用の1行: 日時・差出人・件名・message id。
    var summaryLine: String {
        let dateText = date.map { CLIDateFormatter.shared.string(from: $0) } ?? "----/--/-- --:--"
        let fromText = (from ?? "(差出人不明)").columnTruncated(to: 28)
        let subjectText = (subject ?? "(件名なし)").columnTruncated(to: 48)
        return "\(id)  \(dateText)  \(fromText)  \(subjectText)"
    }
}

enum CLIDateFormatter {
    static let shared: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter
    }()
}

extension String {
    /// 表示幅を揃えるための単純な文字数ベースの切り詰め + パディング。
    func columnTruncated(to width: Int) -> String {
        if count > width {
            return String(prefix(width - 1)) + "…"
        }
        return padding(toLength: width, withPad: " ", startingAt: 0)
    }
}
