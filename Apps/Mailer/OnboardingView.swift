import AuthenticationServices
import MailerCore
import SwiftUI

/// 初回起動時のセットアップ画面。OAuth クライアント ID の入力と Google 認可フローの起動を行う。
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @State private var isAuthorizing = false
    @State private var errorMessage: String?

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "envelope.badge.person.crop")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("Mailer")
                .font(.largeTitle.bold())
            Text("Gmail アカウントを追加して始めましょう。")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Google OAuth クライアント ID (iOS 用)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("xxxx.apps.googleusercontent.com", text: $model.googleClientID)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Text("取得手順はリポジトリの documents/setup-oauth.md を参照")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal)

            Button {
                Task { await addAccount() }
            } label: {
                if isAuthorizing {
                    ProgressView()
                } else {
                    Text("アカウントを追加")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.googleClientID.isEmpty || isAuthorizing)
            .padding(.horizontal)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }
            Spacer()
        }
    }

    private func addAccount() async {
        isAuthorizing = true
        defer { isAuthorizing = false }
        errorMessage = await performAddAccount(model: model, session: webAuthenticationSession)
    }
}
