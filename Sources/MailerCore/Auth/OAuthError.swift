import Foundation

public enum OAuthError: Error, LocalizedError, Equatable {
    case configurationNotFound(URL)
    case stateMismatch
    case authorizationDenied(String)
    case tokenEndpointFailed(statusCode: Int, error: String?, description: String?)
    case missingRefreshToken
    case notAuthorized(email: String)
    case redirectServerClosed

    public var errorDescription: String? {
        switch self {
        case .configurationNotFound(let url):
            return
                "OAuth クライアント設定が見つかりません。\(url.path) に oauth.json を置くか、MAILER_GOOGLE_CLIENT_ID を設定してください。"
        case .stateMismatch:
            return "認可レスポンスの state が一致しません。認可フローをやり直してください。"
        case .authorizationDenied(let reason):
            return "認可が拒否されました: \(reason)"
        case .tokenEndpointFailed(let statusCode, let error, let description):
            let detail = [error, description].compactMap(\.self).joined(separator: ": ")
            return "トークンエンドポイントがエラーを返しました (HTTP \(statusCode)) \(detail)"
        case .missingRefreshToken:
            return
                "リフレッシュトークンが発行されませんでした。https://myaccount.google.com/permissions からアプリのアクセス権を削除して再認可してください。"
        case .notAuthorized(let email):
            return "\(email) は認可されていません。`mailer accounts add` で認可してください。"
        case .redirectServerClosed:
            return "認可待ち受けサーバが閉じられました。"
        }
    }
}
