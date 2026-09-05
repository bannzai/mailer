import ArgumentParser
import MailerCore

@main
struct MailerCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mailer",
        abstract: "bannzai が使うためのメーラー CLI",
        version: Mailer.version,
        subcommands: [
            AccountsCommand.self,
            InboxCommand.self,
            ArchiveCommand.self,
            LabelCommand.self,
            QuickLabelCommand.self,
            NotificationRulesCommand.self,
        ]
    )
}
