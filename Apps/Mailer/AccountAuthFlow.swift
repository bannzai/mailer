import AuthenticationServices
import SwiftUI

/// Google 認可フロー (ASWebAuthenticationSession) を実行してアカウントを追加する。
/// 成功時は nil、失敗時は表示用のエラーメッセージを返す。
@MainActor
func performAddAccount(model: AppModel, session: WebAuthenticationSession) async -> String? {
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
}
