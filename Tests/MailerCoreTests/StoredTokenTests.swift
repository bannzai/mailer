import Foundation
import Testing

@testable import MailerCore

@Test func storedTokenRequiresRefreshToken() {
    let response = TokenResponse(
        accessToken: "at", expiresIn: 3599, refreshToken: nil, scope: nil, tokenType: "Bearer", idToken: nil
    )
    #expect(throws: OAuthError.missingRefreshToken) {
        _ = try StoredToken(response: response)
    }
}

@Test func storedTokenExpiryUsesLeeway() throws {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let token = StoredToken(accessToken: "at", refreshToken: "rt", expiresAt: now.addingTimeInterval(120))
    #expect(token.isExpired(now: now) == false)
    #expect(token.isExpired(now: now.addingTimeInterval(61)) == true)
    #expect(token.isExpired(now: now, leeway: 180) == true)
}

@Test func refreshedTokenKeepsRefreshTokenWhenResponseOmitsIt() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let token = StoredToken(accessToken: "at-old", refreshToken: "rt-keep", expiresAt: now, scope: "scope-a")
    let response = TokenResponse(
        accessToken: "at-new", expiresIn: 3599, refreshToken: nil, scope: nil, tokenType: "Bearer", idToken: nil
    )
    let refreshed = token.refreshed(with: response, now: now)
    #expect(refreshed.accessToken == "at-new")
    #expect(refreshed.refreshToken == "rt-keep")
    #expect(refreshed.scope == "scope-a")
    #expect(refreshed.expiresAt == now.addingTimeInterval(3599))
}
