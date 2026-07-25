import MailerCore
import SwiftUI

/// メール詳細。HTML 本文は WKWebView、無ければプレーンテキストで表示する。
struct MessageDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let messageId: String
    let onArchive: (String) -> Void

    @State private var message: GmailMessage?
    @State private var errorMessage: String?
    @State private var showsQuickLabel = false

    var body: some View {
        Group {
            if let message {
                VStack(alignment: .leading, spacing: 0) {
                    header(message)
                    Divider()
                    bodyContent(message)
                }
            } else if let errorMessage {
                ContentUnavailableView("読み込みに失敗しました", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            } else {
                ProgressView("読み込み中...")
            }
        }
        .navigationTitle(message?.subject ?? "")
        .inlineNavigationBarTitle()
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showsQuickLabel = true
                } label: {
                    Label("ラベル即分け", systemImage: "tag")
                }
                .keyboardShortcut("l", modifiers: [])
                Button {
                    Task { await archive() }
                } label: {
                    Label("アーカイブ", systemImage: "archivebox")
                }
                .keyboardShortcut("e", modifiers: [])
            }
        }
        .sheet(isPresented: $showsQuickLabel) {
            if let message {
                QuickLabelSheet(message: message) { movedMessageIds in
                    if movedMessageIds.contains(message.id) {
                        onArchive(message.id)
                        dismiss()
                    }
                }
            }
        }
        .task {
            await load()
        }
    }

    private func header(_ message: GmailMessage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(message.subject ?? "(件名なし)")
                .font(.headline)
            HStack {
                Text(message.from ?? "(差出人不明)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if let date = message.date {
                    Text(date, format: .dateTime.year().month().day().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
    }

    @ViewBuilder
    private func bodyContent(_ message: GmailMessage) -> some View {
        if let htmlPart = message.payload?.firstPart(mimeType: "text/html"),
            let htmlData = htmlPart.body?.decodedData
        {
            HTMLView(html: String(decoding: htmlData, as: UTF8.self))
        } else if let textPart = message.payload?.firstPart(mimeType: "text/plain"),
            let textData = textPart.body?.decodedData
        {
            ScrollView {
                Text(String(decoding: textData, as: UTF8.self))
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        } else {
            ScrollView {
                Text(message.snippet ?? "(本文なし)")
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
    }

    private func load() async {
        guard let client = model.gmailClient() else { return }
        do {
            message = try await client.getMessage(id: messageId, format: .full)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func archive() async {
        guard let client = model.gmailClient() else { return }
        do {
            try await client.modifyMessage(id: messageId, removeLabelIds: ["INBOX"])
            onArchive(messageId)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
