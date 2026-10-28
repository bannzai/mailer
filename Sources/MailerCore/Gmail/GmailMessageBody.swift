import Foundation

/// 本文の取り出しで起きるエラー。
public enum GmailMessageBodyError: Error, LocalizedError, Equatable {
    /// 本文パートの charset が未知か、そのバイト列を charset で復号できない。
    case undecodableBody(charset: String)
    /// 本文パートが大きく、Gmail が data ではなく attachmentId を返した。本文の取得に別リクエストが要る。
    case bodyRequiresAttachmentFetch(attachmentId: String)

    public var errorDescription: String? {
        switch self {
        case .undecodableBody(let charset):
            return "本文を charset \(charset) として復号できません"
        case .bodyRequiresAttachmentFetch(let attachmentId):
            return "本文が添付 \(attachmentId) として別取得になるため、このメッセージからは本文を取り出せません"
        }
    }
}

extension GmailMessage {
    /// 本文をプレーンテキストとして取り出す。text/plain パートを優先し、無ければ text/html のタグを落としたもの、
    /// どちらも無ければ snippet。添付パート (filename 付き・Content-Disposition: attachment) とその配下は本文とみなさない。
    /// 本文パートは Content-Type の charset (無ければ UTF-8) で復号し、復号できなければ投げる (文字化けした本文を分類に回さない)。
    /// 本文パートが data を持たず attachmentId だけの時も投げる (snippet だけで分類して保存しないため)。
    /// format=full で取得したメッセージでないと payload が無く snippet だけになる。
    public func plainTextBody() throws -> String? {
        if let textPart = payload?.firstBodyPart(mimeType: "text/plain") {
            return try textPart.decodeText(data: try textPart.bodyData())
        }
        if let htmlPart = payload?.firstBodyPart(mimeType: "text/html") {
            return stripHTMLTags(html: try htmlPart.decodeText(data: try htmlPart.bodyData()))
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
    /// 本文が attachmentId で別取得になるパートも本文パートとして返す (snippet へ落とさず bodyData で投げさせるため)。
    func firstBodyPart(mimeType target: String) -> GmailMessagePart? {
        if isAttachment {
            return nil
        }
        if mimeType == target, body?.data != nil || body?.attachmentId != nil {
            return self
        }
        for part in parts ?? [] {
            if let found = part.firstBodyPart(mimeType: target) {
                return found
            }
        }
        return nil
    }

    /// Content-Type ヘッダの charset パラメータ (例: `text/plain; charset="ISO-2022-JP"` の ISO-2022-JP)。無ければ nil。
    /// パラメータは `;` 区切りで、名前と値の間の `=` の前後に空白があってもよい (RFC 2045 の tspecials の扱い)。
    var charset: String? {
        guard
            let contentType = headers?.first(where: { $0.name.caseInsensitiveCompare("Content-Type") == .orderedSame })?
                .value
        else {
            return nil
        }
        for parameter in contentType.split(separator: ";").dropFirst() {
            let pair = parameter.split(separator: "=", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard pair.count == 2, pair[0].caseInsensitiveCompare("charset") == .orderedSame else {
                continue
            }
            return pair[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
        return nil
    }

    /// 本文パートのバイト列。data が無く attachmentId だけの時は GmailMessageBodyError.bodyRequiresAttachmentFetch を投げる。
    func bodyData() throws -> Data {
        if let data = body?.decodedData {
            return data
        }
        guard let attachmentId = body?.attachmentId else {
            return Data()
        }
        throw GmailMessageBodyError.bodyRequiresAttachmentFetch(attachmentId: attachmentId)
    }

    /// パートのバイト列を charset で復号する。charset が無いパートは UTF-8 (us-ascii の上位互換) として読む。
    func decodeText(data: Data) throws -> String {
        let charsetName = charset ?? "utf-8"
        let cfEncoding = CFStringConvertIANACharSetNameToEncoding(charsetName as CFString)
        guard cfEncoding != kCFStringEncodingInvalidId,
            let text = String(
                data: data,
                encoding: String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
            )
        else {
            throw GmailMessageBodyError.undecodableBody(charset: charsetName)
        }
        return text
    }
}

/// HTML からタグを落とし、文字参照 (名前付きの主要なものと 10 進・16 進の数値文字参照) を復号して本文のテキストだけを残す。
/// 分類に送る用途なので、レイアウトの再現はしない。
func stripHTMLTags(html: String) -> String {
    var text = html
    for pattern in ["<style[^>]*>[\\s\\S]*?</style>", "<script[^>]*>[\\s\\S]*?</script>"] {
        text = text.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
    }
    text = text.replacingOccurrences(
        of: "<br\\s*/?>|</p>|</div>|</tr>|</li>", with: "\n", options: [.regularExpression, .caseInsensitive])
    text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    text = decodeNumericCharacterReferences(text: text)
    // &amp; は最後に戻す。先に戻すと "&amp;lt;" のような二重エスケープが "<" に化けるため。
    for (entity, replacement) in [
        ("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&apos;", "'"), ("&amp;", "&"),
    ] {
        text = text.replacingOccurrences(of: entity, with: replacement)
    }
    return text.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

/// `&#36820;` (10 進) と `&#x8FD4;` (16 進) の数値文字参照を文字に戻す。Unicode スカラーにならない値はそのまま残す。
private func decodeNumericCharacterReferences(text: String) -> String {
    let pattern = try! NSRegularExpression(pattern: "&#(?:[xX]([0-9a-fA-F]+)|([0-9]+));")
    let nsText = text as NSString
    var result = ""
    var cursor = 0
    for match in pattern.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
        result += nsText.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
        let hex = match.range(at: 1)
        let codePoint =
            hex.location != NSNotFound
            ? UInt32(nsText.substring(with: hex), radix: 16)
            : UInt32(nsText.substring(with: match.range(at: 2)))
        if let codePoint, let scalar = Unicode.Scalar(codePoint) {
            result.unicodeScalars.append(scalar)
        } else {
            result += nsText.substring(with: match.range)
        }
        cursor = match.range.location + match.range.length
    }
    result += nsText.substring(from: cursor)
    return result
}
