import Foundation
import Testing

@testable import MailerCore

@Test func loopbackServerReceivesAuthorizationCallback() async throws {
    let server = try LoopbackRedirectServer.start()
    defer { server.stop() }
    #expect(server.port > 0)

    let callbackURL = URL(string: "\(server.redirectURI)?code=code-1&state=state-1")!
    let (body, response) = try await URLSession.shared.data(from: callbackURL)
    #expect((response as? HTTPURLResponse)?.statusCode == 200)
    #expect(String(decoding: body, as: UTF8.self).contains("認可が完了しました"))

    let callback = try await server.waitForCallback()
    #expect(callback == LoopbackRedirectServer.Callback(code: "code-1", state: "state-1"))
}

@Test func loopbackServerSurfacesAuthorizationError() async throws {
    let server = try LoopbackRedirectServer.start()
    defer { server.stop() }

    let callbackURL = URL(string: "\(server.redirectURI)?error=access_denied")!
    _ = try await URLSession.shared.data(from: callbackURL)

    await #expect(throws: OAuthError.authorizationDenied("access_denied")) {
        _ = try await server.waitForCallback()
    }
}
