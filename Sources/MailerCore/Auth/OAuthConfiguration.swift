import Foundation

/// Google OAuth クライアントの設定。環境変数または設定ファイル (oauth.json) から読み込む。
public struct OAuthConfiguration: Codable, Sendable, Equatable {
    public var clientID: String
    /// Google の Desktop クライアントは confidential ではないが client_secret が発行される。iOS クライアントでは nil。
    public var clientSecret: String?
    public var scopes: [String]

    public static let defaultScopes = [
        "https://www.googleapis.com/auth/gmail.modify",
        "https://www.googleapis.com/auth/gmail.settings.basic",
    ]

    public init(clientID: String, clientSecret: String? = nil, scopes: [String] = Self.defaultScopes) {
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.scopes = scopes
    }

    /// 環境変数 MAILER_GOOGLE_CLIENT_ID / MAILER_GOOGLE_CLIENT_SECRET を優先し、
    /// 無ければ configDirectory/oauth.json から読み込む。
    public static func load(configDirectory: URL = MailerPaths.configDirectory) throws -> OAuthConfiguration {
        let environment = ProcessInfo.processInfo.environment
        if let clientID = environment["MAILER_GOOGLE_CLIENT_ID"], !clientID.isEmpty {
            return OAuthConfiguration(clientID: clientID, clientSecret: environment["MAILER_GOOGLE_CLIENT_SECRET"])
        }
        let fileURL = configDirectory.appendingPathComponent("oauth.json")
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw OAuthError.configurationNotFound(fileURL)
        }
        let data = try Data(contentsOf: fileURL)
        var configuration = try JSONDecoder().decode(OAuthConfiguration.self, from: data)
        if configuration.scopes.isEmpty {
            configuration.scopes = Self.defaultScopes
        }
        return configuration
    }

    enum CodingKeys: String, CodingKey {
        case clientID
        case clientSecret
        case scopes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        clientID = try container.decode(String.self, forKey: .clientID)
        clientSecret = try container.decodeIfPresent(String.self, forKey: .clientSecret)
        scopes = try container.decodeIfPresent([String].self, forKey: .scopes) ?? Self.defaultScopes
    }
}

/// mailer が使う設定ディレクトリの解決。
public enum MailerPaths {
    /// 環境変数 MAILER_CONFIG_DIR で上書き可能。既定は ~/.config/mailer。
    public static var configDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["MAILER_CONFIG_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("mailer", isDirectory: true)
    }
}
