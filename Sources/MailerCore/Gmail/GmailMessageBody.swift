import Foundation

extension GmailMessage {
    /// 本文をプレーンテキストとして取り出す。text/plain パートを優先し、無ければ text/html のタグを落としたもの、
    /// どちらも無ければ snippet。添付パート (filename 付き・Content-Disposition: attachment) とその配下は本文とみなさない。
    /// format=full で取得したメッセージでないと payload が無く snippet だけになる。
    public var plainTextBody: String? {
        if let textPart = payload?.firstBodyPart(mimeType: "text/plain"), let data = textPart.body?.decodedData {
            return String(decoding: data, as: UTF8.self)
        }
        if let htmlPart = payload?.firstBodyPart(mimeType: "text/html"), let data = htmlPart.body?.decodedData {
            return stripHTMLTags(html: String(decoding: data, as: UTF8.self))
        }
        return snippet
    }
}

extension GmailMessagePart {
    /// 添付パートか。filename が付いているか、Content-Disposition が attachment のもの。
    var isAttachment: Bool {
        if let filename, !filename.isEmpty {
            return true
        }
        return headers?.contains {
            $0.name.caseInsensitiveCompare("Content-Disposition") == .orderedSame
                && $0.value.lowercased().hasPrefix("attachment")
        } == true
    }

    /// firstPart(mimeType:) と同じ深さ優先の探索から、添付パートとその配下を除いたもの。
    func firstBodyPart(mimeType target: String) -> GmailMessagePart? {
        if isAttachment {
            return nil
        }
        if mimeType == target, body?.data != nil {
            return self
        }
        for part in parts ?? [] {
            if let found = part.firstBodyPart(mimeType: target) {
                return found
            }
        }
        return nil
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
