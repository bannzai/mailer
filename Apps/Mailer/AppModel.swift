import Foundation
import MailerCore
import Observation

/// アプリ全体の状態: OAuth 設定・アカウント一覧・選択中アカウント・Gmail クライアント。
@MainActor
@Observable
final class AppModel {
    private(set) var accountList = AccountList()
    var selectedEmail: String?

    private let accountStore = AccountStore()
    private let tokenStore = KeychainTokenStore()
    private var tokenProviders: [String: TokenProvider] = [:]

    /// Google の iOS 用 OAuth クライアント ID。シークレットではないため UserDefaults に保存する。
    var googleClientID: String {
        didSet {
            UserDefaults.standard.set(googleClientID, forKey: Self.clientIDDefaultsKey)
        }
    }

    static let clientIDDefaultsKey = "GoogleOAuthClientID"

    init() {
        googleClientID = UserDefaults.standard.string(forKey: Self.clientIDDefaultsKey) ?? ""
        reloadAccounts()
    }

    var configuration: OAuthConfiguration? {
        googleClientID.isEmpty ? nil : OAuthConfiguration(clientID: googleClientID)
    }

    var accountManager: AccountManager? {
        configuration.map {
            AccountManager(configuration: $0, tokenStore: tokenStore, accountStore: accountStore)
        }
    }

    func reloadAccounts() {
        accountList = (try? accountStore.load()) ?? AccountList()
        if selectedEmail == nil || !accountList.accounts.contains(where: { $0.email == selectedEmail }) {
            selectedEmail = accountList.defaultAccount
        }
    }

    /// 選択中アカウントの Gmail クライアント。TokenProvider はアカウントごとに使い回す。
    func gmailClient() -> GmailClient? {
        guard let selectedEmail, let configuration else { return nil }
        let provider: TokenProvider
        if let cached = tokenProviders[selectedEmail] {
            provider = cached
        } else {
            provider = TokenProvider(
                oauth: GoogleOAuthClient(configuration: configuration),
                tokenStore: tokenStore
            )
            tokenProviders[selectedEmail] = provider
        }
        return GmailClient(email: selectedEmail, tokenProvider: provider)
    }

    func selectAccount(_ email: String) {
        selectedEmail = email
        try? accountStore.setDefault(email: email)
        reloadAccounts()
    }

    // MARK: - 認可フロー (ASWebAuthenticationSession)

    /// 認可開始に必要な材料。completeAuthorization にそのまま渡す。
    struct AuthorizationRequest {
        let url: URL
        let pkce: PKCE
        let state: String
        let redirectURI: String
        let callbackScheme: String
    }

    func beginAuthorization() throws -> AuthorizationRequest {
        guard let configuration else {
            throw OAuthError.configurationNotFound(URL(fileURLWithPath: "UserDefaults:GoogleOAuthClientID"))
        }
        guard let scheme = GoogleOAuthClient.redirectScheme(forClientID: configuration.clientID) else {
            throw OAuthError.authorizationDenied("クライアント ID の形式が不正です: \(configuration.clientID)")
        }
        let pkce = PKCE()
        let state = PKCE.randomVerifier()
        let redirectURI = "\(scheme):/oauth2redirect"
        return AuthorizationRequest(
            url: GoogleOAuthClient(configuration: configuration).authorizationURL(
                redirectURI: redirectURI,
                pkce: pkce,
                state: state
            ),
            pkce: pkce,
            state: state,
            redirectURI: redirectURI,
            callbackScheme: scheme
        )
    }

    func completeAuthorization(callbackURL: URL, request: AuthorizationRequest) async throws {
        guard let accountManager else {
            throw OAuthError.configurationNotFound(URL(fileURLWithPath: "UserDefaults:GoogleOAuthClientID"))
        }
        let queryItems = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let errorValue = queryItems.first(where: { $0.name == "error" })?.value {
            throw OAuthError.authorizationDenied(errorValue)
        }
        guard let code = queryItems.first(where: { $0.name == "code" })?.value,
            queryItems.first(where: { $0.name == "state" })?.value == request.state
        else {
            throw OAuthError.stateMismatch
        }
        let record = try await accountManager.completeAuthorization(
            code: code,
            pkce: request.pkce,
            redirectURI: request.redirectURI
        )
        reloadAccounts()
        selectedEmail = record.email
    }

    func removeAccount(email: String) async throws {
        try await accountManager?.removeAccount(email: email)
        tokenProviders[email] = nil
        reloadAccounts()
    }
}
