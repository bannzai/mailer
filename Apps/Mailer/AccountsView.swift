import LicenseList
import MailerCore
import SwiftUI

/// アカウントの一覧・追加・削除・切り替えを行う管理画面。
struct AccountsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @Environment(\.dismiss) private var dismiss

    @State private var isAuthorizing = false
    @State private var errorMessage: String?
    @State private var removalTarget: AccountRecord?

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            List {
                Section("アカウント") {
                    ForEach(model.accountList.accounts) { record in
                        Button {
                            model.selectAccount(record.email)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                AccountBadge(email: record.email, size: 36)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(record.email)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    if record.email == model.accountList.defaultAccount {
                                        Text("既定")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if record.email == model.selectedEmail {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                removalTarget = record
                            } label: {
                                Label("削除", systemImage: "trash")
                            }
                        }
                    }
                }

                #if os(iOS)
                    if model.googleClientID.isEmpty {
                        Section("Google OAuth クライアント ID (iOS 用)") {
                            TextField("xxxx.apps.googleusercontent.com", text: $model.googleClientID)
                                .autocorrectionDisabled()
                                .disableAutocapitalization()
                        }
                    }
                #else
                    if model.configuration == nil {
                        Section {
                            Text("~/.config/mailer/oauth.json に OAuth クライアント設定を置いてください (documents/setup-oauth.md 参照)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                #endif

                Section {
                    Button {
                        Task { await addAccount() }
                    } label: {
                        if isAuthorizing {
                            ProgressView()
                        } else {
                            Label("アカウントを追加", systemImage: "person.badge.plus")
                        }
                    }
                    .disabled(model.configuration == nil || isAuthorizing)
                } footer: {
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }

                Section("このアプリについて") {
                    NavigationLink {
                        LicenseListView()
                            .licenseViewStyle(.withRepositoryAnchorLink)
                            .navigationTitle("OSS ライセンス")
                            .inlineNavigationBarTitle()
                    } label: {
                        Label("OSS ライセンス", systemImage: "doc.text")
                    }
                }
            }
            .navigationTitle("アカウント管理")
            .inlineNavigationBarTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .confirmationDialog(
                "\(removalTarget?.email ?? "") を削除しますか?",
                isPresented: Binding(
                    get: { removalTarget != nil },
                    set: { if !$0 { removalTarget = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("削除 (トークンも失効)", role: .destructive) {
                    if let removalTarget {
                        Task { await remove(removalTarget) }
                    }
                }
            }
        }
        #if os(macOS)
            .frame(minWidth: 440, minHeight: 360)
        #endif
    }

    private func addAccount() async {
        isAuthorizing = true
        defer { isAuthorizing = false }
        errorMessage = await performAddAccount(model: model, session: webAuthenticationSession)
    }

    private func remove(_ record: AccountRecord) async {
        do {
            try await model.removeAccount(email: record.email)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
