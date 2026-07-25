import MailerCore
import SwiftUI

/// 受信トレイ一覧。スワイプでアーカイブ / ラベル即分けを行う。
struct InboxView: View {
    @Environment(AppModel.self) private var model
    @State private var messages: [GmailMessage] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var quickLabelTarget: GmailMessage?
    @State private var showsAccountsSheet = false

    var body: some View {
        Group {
            if isLoading && messages.isEmpty {
                ProgressView("読み込み中...")
            } else if messages.isEmpty {
                ContentUnavailableView(
                    "受信トレイは空です",
                    systemImage: "tray",
                    description: Text(Self.refreshHint)
                )
            } else {
                messageList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("受信トレイ")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    Task { await reload() }
                } label: {
                    Label("更新", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)
                accountMenu
            }
        }
        .task(id: model.selectedEmail) {
            await reload()
        }
        .refreshable {
            await reload()
        }
        .sheet(item: $quickLabelTarget) { message in
            QuickLabelSheet(message: message) { movedMessageIds in
                messages.removeAll { movedMessageIds.contains($0.id) }
            }
        }
        .sheet(isPresented: $showsAccountsSheet) {
            AccountsView()
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            currentAccountBar
        }
        .overlay(alignment: .bottom) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .padding(8)
                    .background(.red.opacity(0.9), in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(.white)
                    .padding()
            }
        }
    }

    private var messageList: some View {
        List(messages) { message in
            NavigationLink(value: message.id) {
                MessageRow(message: message)
            }
            .swipeActions(edge: .trailing) {
                Button {
                    Task { await archive(message) }
                } label: {
                    Label("アーカイブ", systemImage: "archivebox")
                }
                .tint(.green)
            }
            .swipeActions(edge: .leading) {
                Button {
                    quickLabelTarget = message
                } label: {
                    Label("ラベル即分け", systemImage: "tag")
                }
                .tint(.indigo)
            }
        }
        .listStyle(.plain)
        .navigationDestination(for: String.self) { messageId in
            MessageDetailView(messageId: messageId) { archivedId in
                messages.removeAll { $0.id == archivedId }
            }
        }
    }

    static let refreshHint: String = {
        #if os(macOS)
            return "⌘R で更新できます"
        #else
            return "引っ張って更新できます"
        #endif
    }()

    /// どのアカウントを見ているかを常に判別できるよう、一覧の上に識別色バッジ + メールアドレスを固定表示する。
    private var currentAccountBar: some View {
        HStack(spacing: 8) {
            if let selectedEmail = model.selectedEmail {
                AccountBadge(email: selectedEmail, size: 20)
                Text(selectedEmail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private var accountMenu: some View {
        Menu {
            ForEach(model.accountList.accounts) { record in
                Button {
                    model.selectAccount(record.email)
                } label: {
                    if record.email == model.selectedEmail {
                        Label(record.email, systemImage: "checkmark")
                    } else {
                        Text(record.email)
                    }
                }
            }
            Divider()
            Button {
                showsAccountsSheet = true
            } label: {
                Label("アカウント管理...", systemImage: "person.2.badge.gearshape")
            }
        } label: {
            if let selectedEmail = model.selectedEmail {
                AccountBadge(email: selectedEmail, size: 28)
            } else {
                Image(systemName: "person.crop.circle")
            }
        }
    }

    private func reload() async {
        guard let client = model.gmailClient() else { return }
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            // 一覧の初期表示に十分で、metadata の並行フェッチが数秒で終わる件数として 50 件に制限。
            let refs = try await client.listMessages(labelIds: ["INBOX"], maxResults: 50).messages ?? []
            messages = try await withThrowingTaskGroup(of: (Int, GmailMessage).self) { group in
                for (index, ref) in refs.enumerated() {
                    group.addTask {
                        (
                            index,
                            try await client.getMessage(
                                id: ref.id,
                                format: .metadata(headers: ["From", "Subject"])
                            )
                        )
                    }
                }
                var fetched: [(Int, GmailMessage)] = []
                for try await result in group {
                    fetched.append(result)
                }
                return fetched.sorted { $0.0 < $1.0 }.map(\.1)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func archive(_ message: GmailMessage) async {
        guard let client = model.gmailClient() else { return }
        do {
            try await client.modifyMessage(id: message.id, removeLabelIds: ["INBOX"])
            messages.removeAll { $0.id == message.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// 一覧の1行: 差出人・件名・スニペット・日時。
struct MessageRow: View {
    let message: GmailMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(senderDisplayName)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                Spacer()
                if let date = message.date {
                    Text(date, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text(message.subject ?? "(件名なし)")
                .font(.subheadline)
                .lineLimit(1)
            if let snippet = message.snippet, !snippet.isEmpty {
                Text(snippet)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }

    private var senderDisplayName: String {
        guard let from = message.from else { return "(差出人不明)" }
        if let bracketIndex = from.firstIndex(of: "<"), bracketIndex != from.startIndex {
            return String(from[..<bracketIndex])
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        return from
    }
}
