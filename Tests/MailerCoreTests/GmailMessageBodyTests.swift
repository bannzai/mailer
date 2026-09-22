import Foundation
import Testing

@testable import MailerCore

private func base64url(_ text: String) -> String {
    Data(text.utf8).base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
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

@Test func plainTextBodySkipsAttachmentsAndTheirChildren() {
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
    #expect(message.plainTextBody == "本文")
}

@Test func plainTextBodyPrefersTextPlainPart() {
    let message = makeMessage(parts: [
        makePart(mimeType: "text/html", text: "<p>HTML 本文</p>"),
        makePart(mimeType: "text/plain", text: "テキスト本文"),
    ])
    #expect(message.plainTextBody == "テキスト本文")
}

@Test func plainTextBodyStripsHTMLWhenNoPlainPart() {
    let message = makeMessage(parts: [
        makePart(
            mimeType: "text/html",
            text: "<html><style>p{}</style><body><p>起動しない&amp;落ちる</p><br><div>返金してください</div></body></html>"
        )
    ])
    #expect(message.plainTextBody == "起動しない&落ちる\n\n返金してください")
}

@Test func plainTextBodyFallsBackToSnippet() {
    #expect(makeMessage(snippet: "スニペット", parts: []).plainTextBody == "スニペット")
}

@Test func inputTextPrefixesSubjectAndTruncates() {
    let longBody = String(repeating: "あ", count: 3000)
    let message = makeMessage(subject: "起動しない", parts: [makePart(mimeType: "text/plain", text: "  \(longBody)\n")])
    let text = InquiryClassificationPipeline.inputText(message: message)
    #expect(text.hasPrefix("件名: 起動しない\n\nあ"))
    #expect(text.count == InquiryClassificationPipeline.maxInputCharacters)
}

@Test func inputTextOmitsSubjectLineWhenMissing() {
    let message = makeMessage(parts: [makePart(mimeType: "text/plain", text: "本文だけ")])
    #expect(InquiryClassificationPipeline.inputText(message: message) == "本文だけ")
}
