import Foundation

/// アカウントの追加 (認可フロー)・削除・一覧を提供する高水準 API。
public struct AccountManager: Sendable {
    let configuration: OAuthConfiguration
    let transport: HTTPTransport
    let tokenStore: TokenStore
    let accountStore: AccountStore
    /// アカウント削除時に、そのアカウントの通知状態 (保留中メール・最終通知時刻) も消すための保存先。
    let notificationStateStore: NotificationStateStore

    public init(
        configuration: OAuthConfiguration,
        transport: HTTPTransport = URLSessionTransport(),
        tokenStore: TokenStore = KeychainTokenStore(),
        accountStore: AccountStore = AccountStore(),
        notificationStateStore: NotificationStateStore = NotificationStateStore()
    ) {
        self.configuration = configuration
        self.transport = transport
        self.tokenStore = tokenStore
        self.accountStore = accountStore
        self.notificationStateStore = notificationStateStore
    }

    public var oauthClient: GoogleOAuthClient {
        GoogleOAuthClient(configuration: configuration, transport: transport)
    }

    /// CLI 向け: loopback リダイレクトで認可フローを実行し、アカウントを登録する。
    /// openURL には認可 URL をブラウザで開く処理を渡す。
    public func addAccountViaLoopback(
        loginHint: String? = nil,
        openURL: @Sendable (URL) throws -> Void
    ) async throws -> AccountRecord {
        let server = try LoopbackRedirectServer.start()
        defer { server.stop() }
        let pkce = PKCE()
        let state = PKCE.randomVerifier()
        let url = oauthClient.authorizationURL(
            redirectURI: server.redirectURI,
            pkce: pkce,
            state: state,
            loginHint: loginHint
        )
        try openURL(url)
        let callback = try await server.waitForCallback()
        guard callback.state == state else {
            throw OAuthError.stateMismatch
        }
        return try await completeAuthorization(
            code: callback.code,
            pkce: pkce,
            redirectURI: server.redirectURI
        )
    }

    /// 認可コードをトークンに交換し、プロフィールからメールアドレスを解決して登録する。
    /// アプリ側 (ASWebAuthenticationSession) のフローもコード取得後はここに合流する。
    public func completeAuthorization(
        code: String,
        pkce: PKCE,
        redirectURI: String
    ) async throws -> AccountRecord {
        let response = try await oauthClient.exchangeCode(code, pkce: pkce, redirectURI: redirectURI)
        let token = try StoredToken(response: response)
        let profile = try await ProfileClient(transport: transport).fetch(accessToken: token.accessToken)
        try tokenStore.save(token, for: profile.emailAddress)
        return try accountStore.add(email: profile.emailAddress)
    }

    /// アカウントを削除する。トークンの失効に失敗してもローカルの削除は続行する (冪等)。
    /// 通知状態 (保留中メール・最終通知時刻) も消し、同じアドレスで再追加した時に古い状態が残らないようにする。
    public func removeAccount(email: String) async throws {
        if let token = try? tokenStore.load(for: email) {
            try? await oauthClient.revoke(token: token.refreshToken)
        }
        try tokenStore.delete(for: email)
        try accountStore.remove(email: email)
        try notificationStateStore.remove(account: email)
    }

    public func accounts() throws -> AccountList {
        try accountStore.load()
    }

    public func setDefaultAccount(email: String) throws {
        try accountStore.setDefault(email: email)
    }

    public func tokenProvider() -> TokenProvider {
        TokenProvider(oauth: oauthClient, tokenStore: tokenStore)
    }
}
