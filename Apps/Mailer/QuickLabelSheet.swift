import MailerCore
import SwiftUI

/// メールを起点にラベル即分け (quicklabel) を実行するシート。
/// 条件 (差出人 / ドメイン / 件名) とラベル名を選んで、ラベル作成 + フィルタ作成 + 既存メール移動を一括実行する。
struct QuickLabelSheet: View {
    /// 振り分け条件の種類。
    enum ConditionKind: String, CaseIterable, Identifiable {
        case fromAddress = "差出人"
        case fromDomain = "ドメイン"
        case subject = "件名"

        var id: String { rawValue }
    }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let message: GmailMessage
    /// 実行後、Inbox から消えたメール id を親リストへ通知する。
    let onMoved: ([String]) -> Void

    @State private var conditionKind: ConditionKind = .fromAddress
    @State private var labelName = ""
    @State private var subjectText = ""
    @State private var isRunning = false
    @State private var resultText: String?
    @State private var errorMessage: String?

    private var senderAddress: String? {
        message.from.flatMap { EmailAddress.extract(fromHeader: $0) }
    }

    private var senderDomain: String? {
        senderAddress.flatMap { EmailAddress.domain(of: $0) }
    }

    private var condition: QuickLabelCondition? {
        switch conditionKind {
        case .fromAddress:
            return senderAddress.map { .fromAddress($0) }
        case .fromDomain:
            return senderDomain.map { .fromDomain($0) }
        case .subject:
            return subjectText.isEmpty ? nil : .subjectContains(subjectText)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("条件") {
                    Picker("種類", selection: $conditionKind) {
                        ForEach(ConditionKind.allCases) { kind in
                            Text(kind.rawValue).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)

                    switch conditionKind {
                    case .fromAddress:
                        LabeledContent("差出人", value: senderAddress ?? "取得できません")
                    case .fromDomain:
                        LabeledContent("ドメイン", value: senderDomain ?? "取得できません")
                    case .subject:
                        TextField("件名に含まれる文字列", text: $subjectText)
                    }
                }

                Section("ラベル") {
                    TextField("ラベル名", text: $labelName)
                        .autocorrectionDisabled()
                }

                Section {
                    Button {
                        Task { await run() }
                    } label: {
                        if isRunning {
                            ProgressView()
                        } else {
                            Text("実行 (ラベル + フィルタ作成 & 既存メール移動)")
                        }
                    }
                    .disabled(labelName.isEmpty || condition == nil || isRunning)
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        if let resultText {
                            Text(resultText)
                        }
                        if let errorMessage {
                            Text(errorMessage).foregroundStyle(.red)
                        }
                    }
                }
            }
            .navigationTitle("ラベル即分け")
            .inlineNavigationBarTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .onAppear {
                if labelName.isEmpty, let senderDomain {
                    labelName = senderDomain
                }
            }
        }
        #if os(macOS)
            .frame(minWidth: 440, minHeight: 420)
        #endif
    }

    private func run() async {
        guard let client = model.gmailClient(), let condition else { return }
        isRunning = true
        defer { isRunning = false }
        errorMessage = nil
        do {
            let result = try await client.quickLabel(condition: condition, labelName: labelName)
            resultText =
                "ラベル「\(result.label.name)」に\(result.filterCreated ? "フィルタを作成し、" : "既存フィルタを再利用し、")既存 \(result.movedMessageCount)件を移動しました。"
            onMoved([message.id])
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
