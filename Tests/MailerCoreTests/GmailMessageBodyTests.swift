import Foundation
import Testing

@testable import MailerCore

private func base64url(_ text: String) -> String {
    base64url(Data(text.utf8))
}

private func base64url(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

/// charset 付きの text/plain パート。bytes をそのまま本文にする。
private func makeEncodedPart(mimeType: String, bytes: Data, charset: String) -> GmailMessagePart {
    GmailMessagePart(
        partId: nil,
        mimeType: mimeType,
        filename: nil,
        headers: [GmailHeader(name: "Content-Type", value: "\(mimeType); charset=\"\(charset)\"")],
        body: GmailMessagePartBody(size: bytes.count, data: base64url(bytes)),
        parts: nil
    )
}

@Test func plainTextBodyDecodesPartCharset() throws {
    let iso2022 = try #require("返金してください".data(using: .iso2022JP))
    let shiftJIS = try #require("起動しない".data(using: .shiftJIS))
    #expect(
        try makeMessage(parts: [makeEncodedPart(mimeType: "text/plain", bytes: iso2022, charset: "ISO-2022-JP")])
            .plainTextBody() == "返金してください")
    #expect(
        try makeMessage(parts: [makeEncodedPart(mimeType: "text/html", bytes: shiftJIS, charset: "Shift_JIS")])
            .plainTextBody() == "起動しない")
}

@Test func charsetParameterAllowsWhitespaceAroundEqualsAndOtherParameters() throws {
    let iso2022 = try #require("返金してください".data(using: .iso2022JP))
    let part = GmailMessagePart(
        partId: nil,
        mimeType: "text/plain",
        filename: nil,
        headers: [GmailHeader(name: "content-type", value: "text/plain; format=flowed; Charset = 'ISO-2022-JP' ; x=1")],
        body: GmailMessagePartBody(size: iso2022.count, data: base64url(iso2022)),
        parts: nil
    )
    #expect(part.charset == "ISO-2022-JP")
    #expect(try makeMessage(parts: [part]).plainTextBody() == "返金してください")
    #expect(
        makePart(mimeType: "text/plain", text: "x", headers: [GmailHeader(name: "Content-Type", value: "text/plain")])
            .charset == nil)
}

@Test func plainTextBodyThrowsWhenCharsetCannotDecode() throws {
    let message = makeMessage(
        snippet: "スニペット",
        parts: [makeEncodedPart(mimeType: "text/plain", bytes: Data([0xFF, 0xFE, 0xFD]), charset: "utf-8")]
    )
    #expect(throws: GmailMessageBodyError.undecodableBody(charset: "utf-8")) {
        try message.plainTextBody()
    }
    let unknown = makeMessage(parts: [makeEncodedPart(mimeType: "text/plain", bytes: Data("x".utf8), charset: "x-nope")]
    )
    #expect(throws: GmailMessageBodyError.undecodableBody(charset: "x-nope")) {
        try unknown.plainTextBody()
    }
}

@Test func stripHTMLTagsDecodesNumericCharacterReferences() {
    #expect(stripHTMLTags(html: "<p>&#36820;&#37329;&#x3057;&#X3066;</p>") == "返金して")
    #expect(stripHTMLTags(html: "a&amp;lt;b &#39;c&#39; &#99999999;") == "a&lt;b 'c' &#99999999;")
}

private func makeMessage(subject: String? = nil, snippet: String? = nil, parts: [GmailMessagePart]) -> GmailMessage {
    GmailMessage(
        id: "m1",
        threadId: nil,
        labelIds: nil,
        snippet: snippet,
        historyId: nil,
        internalDate: nil,
        payload: GmailMessagePart(
            partId: nil,
            mimeType: "multipart/alternative",
            filename: nil,
            headers: subject.map { [GmailHeader(name: "Subject", value: $0)] },
            body: nil,
            parts: parts
        ),
        sizeEstimate: nil
    )
}

private func makePart(
    mimeType: String,
    text: String,
    filename: String? = nil,
    headers: [GmailHeader]? = nil
) -> GmailMessagePart {
    GmailMessagePart(
        partId: nil,
        mimeType: mimeType,
        filename: filename,
        headers: headers,
        body: GmailMessagePartBody(size: text.utf8.count, data: base64url(text)),
        parts: nil
    )
}

@Test func plainTextBodySkipsAttachmentsAndTheirChildren() throws {
    let message = makeMessage(parts: [
        makePart(mimeType: "text/plain", text: "添付のテキスト", filename: "log.txt"),
        makePart(
            mimeType: "text/plain",
            text: "inline 指定の添付",
            headers: [GmailHeader(name: "Content-Disposition", value: "attachment; filename=\"a.txt\"")]
        ),
        GmailMessagePart(
            partId: nil,
            mimeType: "multipart/mixed",
            filename: "bundle.eml",
            headers: nil,
            body: nil,
            parts: [makePart(mimeType: "text/plain", text: "添付の中の本文")]
        ),
        makePart(mimeType: "text/html", text: "<p>本文</p>"),
    ])
    #expect(try message.plainTextBody() == "本文")
}

@Test func plainTextBodyPrefersTextPlainPart() throws {
    let message = makeMessage(parts: [
        makePart(mimeType: "text/html", text: "<p>HTML 本文</p>"),
        makePart(mimeType: "text/plain", text: "テキスト本文"),
    ])
    #expect(try message.plainTextBody() == "テキスト本文")
}

@Test func plainTextBodyStripsHTMLWhenNoPlainPart() throws {
    let message = makeMessage(parts: [
        makePart(
            mimeType: "text/html",
            text: "<html><style>p{}</style><body><p>起動しない&amp;落ちる</p><br><div>返金してください</div></body></html>"
        )
    ])
    #expect(try message.plainTextBody() == "起動しない&落ちる\n\n返金してください")
}

@Test func plainTextBodyFallsBackToSnippet() throws {
    #expect(try makeMessage(snippet: "スニペット", parts: []).plainTextBody() == "スニペット")
}

@Test func inputTextPrefixesSubjectAndTruncates() throws {
    let longBody = String(repeating: "あ", count: 3000)
    let message = makeMessage(subject: "起動しない", parts: [makePart(mimeType: "text/plain", text: "  \(longBody)\n")])
    let text = try InquiryClassificationPipeline.inputText(message: message)
    #expect(text.hasPrefix("件名: 起動しない\n\nあ"))
    #expect(text.count == InquiryClassificationPipeline.maxInputCharacters)
}

@Test func inputTextOmitsSubjectLineWhenMissing() throws {
    let message = makeMessage(parts: [makePart(mimeType: "text/plain", text: "本文だけ")])
    #expect(try InquiryClassificationPipeline.inputText(message: message) == "本文だけ")
}
