import Foundation

extension GmailMessage {
    /// 本文をプレーンテキストとして取り出す。text/plain パートを優先し、無ければ text/html のタグを落としたもの、
    /// どちらも無ければ snippet。format=full で取得したメッセージでないと payload が無く snippet だけになる。
    public var plainTextBody: String? {
        if let textPart = payload?.firstPart(mimeType: "text/plain"), let data = textPart.body?.decodedData {
            return String(decoding: data, as: UTF8.self)
        }
        if let htmlPart = payload?.firstPart(mimeType: "text/html"), let data = htmlPart.body?.decodedData {
            return stripHTMLTags(html: String(decoding: data, as: UTF8.self))
        }
        return snippet
    }
}

/// HTML からタグを落として本文のテキストだけを残す。分類に送る用途なので、レイアウトの再現はしない。
func stripHTMLTags(html: String) -> String {
    var text = html
    for pattern in ["<style[^>]*>[\\s\\S]*?</style>", "<script[^>]*>[\\s\\S]*?</script>"] {
        text = text.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
    }
    text = text.replacingOccurrences(
        of: "<br\\s*/?>|</p>|</div>|</tr>|</li>", with: "\n", options: [.regularExpression, .caseInsensitive])
    text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    for (entity, replacement) in [
        ("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"),
    ] {
        text = text.replacingOccurrences(of: entity, with: replacement)
    }
    return text.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}
