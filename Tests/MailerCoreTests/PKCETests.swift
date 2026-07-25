import Testing

@testable import MailerCore

@Test func pkceChallengeMatchesRFC7636TestVector() {
    let pkce = PKCE(codeVerifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
    #expect(pkce.codeChallenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
}

@Test func pkceVerifierUsesUnreservedCharactersWithValidLength() {
    let pkce = PKCE()
    let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
    #expect(pkce.codeVerifier.allSatisfy { allowed.contains($0) })
    #expect((43...128).contains(pkce.codeVerifier.count))
}

@Test func pkceVerifierIsRandomPerInstance() {
    #expect(PKCE().codeVerifier != PKCE().codeVerifier)
}
