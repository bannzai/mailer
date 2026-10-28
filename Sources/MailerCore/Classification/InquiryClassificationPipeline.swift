import Foundation

/// 受信したメール集合に対する分類の実行結果。
public struct InquiryClassificationRun: Sendable, Equatable {
    /// メール ID -> 判定結果 (保存済みのものと今回判定したものの両方)。
    public let classifications: [String: InquiryClassification]
    /// 今回新たに判定して保存したメール ID (入力順)。
    public let classifiedMessageIds: [String]
    /// 判定できなかったメール ID (入力順)。分類なしとして既存の通知経路に流す。
    public let unavailableMessageIds: [String]
    /// 判定できなかった理由 (API キー・質問定義が無い、API 不達・タイムアウト等)。判定できなかったメールが無ければ nil。
    public let unavailableReason: String?

    public init(
        classifications: [String: InquiryClassification],
        classifiedMessageIds: [String],
        unavailableMessageIds: [String],
        unavailableReason: String?
    ) {
        self.classifications = classifications
        self.classifiedMessageIds = classifiedMessageIds
        self.unavailableMessageIds = unavailableMessageIds
        self.unavailableReason = unavailableReason
    }
}

/// 受信処理の分類ステップ。未判定のメールだけ本文を取得して Jev に送り、結果を保存する。
/// API 不達・タイムアウト・設定不足では投げず、そのメールを「判定なし」として返す (不達を「問題なし」にしない)。
public struct InquiryClassificationPipeline: Sendable {
    /// Jev に送る本文の最大文字数 (件名を含む)。問い合わせの本文は通常数百文字で、それより長いのは引用の返信連鎖や署名のため、
    /// 先頭だけで判定できる。Jev の state + 質問の上限 32k トークン (https://docs.typesafe.ai/model-jaggedness/jev-1.13.md)
    /// より十分小さく、1 件の入力を 3,000 トークン前後 ($0.00013 未満) に抑える。
    public static let maxInputCharacters = 2000

    /// 未判定のメールの本文を format=full で取り直すための Gmail クライアント (保存先のアカウントもここから取る)。
    let gmail: GmailClient
    /// nil なら API キーか質問定義が無い環境 (iOS 等)。全メールを判定なしとして返す。
    let classifier: InquiryClassifier?
    /// 判定結果の保存先。保存済みのメールは API を呼ばない。
    let store: InquiryClassificationStore

    public init(gmail: GmailClient, classifier: InquiryClassifier?, store: InquiryClassificationStore) {
        self.gmail = gmail
        self.classifier = classifier
        self.store = store
    }

    /// Jev に送るテキスト。件名を 1 行目に置き、本文を続けて maxInputCharacters に切り詰める。
    /// 本文を charset で復号できないメールは投げる (文字化けした本文の判定を保存しないため)。
    public static func inputText(message: GmailMessage) throws -> String {
        let subject = message.subject.map { "件名: \($0)\n\n" } ?? ""
        let body = try message.plainTextBody()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return String((subject + body).prefix(maxInputCharacters))
    }

    /// メール集合を分類する。保存済みのメールは API を呼ばず保存値を返す (冪等)。
    /// メールは metadata 形式でよく、未判定のものだけ format=full で本文を取り直す。
    /// API が 1 度失敗したら、残りのメールは判定なしにして API を呼ばない (不達時に件数分待たないため)。
    /// 本文を復号できないメールはそのメールだけ判定なしにし、残りは続ける。
    public func classify(messages: [GmailMessage]) async -> InquiryClassificationRun {
        var stored = (try? store.load(account: gmail.email)) ?? [:]
        var result: [String: InquiryClassification] = [:]
        var classifiedMessageIds: [String] = []
        var unavailableMessageIds: [String] = []
        var unavailableReason: String? = classifier == nil ? "TYPESAFE_API_KEY か質問定義が無いため分類を利用できません" : nil
        // 本文を復号できないメールの理由。API の失敗と違い残りのメールは続けるため、unavailableReason とは分けて持つ。
        var undecodableReason: String?

        for message in messages {
            if let existing = stored[message.id] {
                result[message.id] = existing
                continue
            }
            guard let classifier, unavailableReason == nil else {
                unavailableMessageIds.append(message.id)
                continue
            }
            do {
                let classification = try await classifier.classify(
                    text: try Self.inputText(message: try await gmail.getMessage(id: message.id, format: .full))
                )
                stored[message.id] = classification
                try store.save(stored, account: gmail.email)
                result[message.id] = classification
                classifiedMessageIds.append(message.id)
            } catch let error as GmailMessageBodyError {
                undecodableReason = error.localizedDescription
                unavailableMessageIds.append(message.id)
            } catch {
                unavailableReason = error.localizedDescription
                unavailableMessageIds.append(message.id)
            }
        }
        return InquiryClassificationRun(
            classifications: result,
            classifiedMessageIds: classifiedMessageIds,
            unavailableMessageIds: unavailableMessageIds,
            unavailableReason: unavailableMessageIds.isEmpty ? nil : (unavailableReason ?? undecodableReason)
        )
    }
}
