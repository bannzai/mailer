import CryptoKit
import Foundation

/// RFC 7636 Proof Key for Code Exchange の code_verifier / code_challenge (S256)。
public struct PKCE: Sendable {
    public let codeVerifier: String
    public let codeChallenge: String

    public init() {
        self.init(codeVerifier: Self.randomVerifier())
    }

    public init(codeVerifier: String) {
        self.codeVerifier = codeVerifier
        self.codeChallenge = Self.challenge(for: codeVerifier)
    }

    static func randomVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        for index in bytes.indices {
            bytes[index] = UInt8.random(in: .min ... .max)
        }
        return Data(bytes).base64URLEncodedString()
    }

    static func challenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }
}

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
