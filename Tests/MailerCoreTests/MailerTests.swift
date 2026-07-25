import Testing

@testable import MailerCore

@Test func versionIsSemanticVersion() {
    let components = Mailer.version.split(separator: ".")
    #expect(components.count == 3)
    #expect(components.allSatisfy { Int($0) != nil })
}
