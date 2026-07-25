import AuthenticationServices
import SwiftUI

#if os(macOS)
    import AppKit
#endif

/// Google 認可フローを実行してアカウントを追加する。成功時は nil、失敗時は表示用のエラーメッセージを返す。
/// iOS は ASWebAuthenticationSession + カスタムスキーム、macOS は CLI と同じ loopback リダイレクト + 既定ブラウザを使う。
@MainActor
func performAddAccount(model: AppModel, session: WebAuthenticationSession) async -> String? {
    #if os(macOS)
        guard let accountManager = model.accountManager else {
            return "OAuth クライアント設定 (~/.config/mailer/oauth.json) が見つかりません。documents/setup-oauth.md を参照してください。"
        }
        do {
            let record = try await accountManager.addAccountViaLoopback { url in
                _ = NSWorkspace.shared.open(url)
            }
            model.reloadAccounts()
            model.selectedEmail = record.email
            return nil
        } catch {
            return error.localizedDescription
        }
    #else
        do {
            let request = try model.beginAuthorization()
            try await model.completeAuthorization(
                callbackURL: try await session.authenticate(
                    using: request.url,
                    callbackURLScheme: request.callbackScheme
                ),
                request: request
            )
            return nil
        } catch is ASWebAuthenticationSessionError {
            return "認可がキャンセルされました。"
        } catch {
            return error.localizedDescription
        }
    #endif
}
