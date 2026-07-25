import SwiftUI

extension View {
    /// iOS のみ: ナビゲーションバータイトルを inline 表示にする。macOS には同 API が無い。
    func inlineNavigationBarTitle() -> some View {
        #if os(iOS)
            return navigationBarTitleDisplayMode(.inline)
        #else
            return self
        #endif
    }

    /// iOS のみ: テキスト入力の自動大文字化を無効にする。macOS には同 API が無い。
    func disableAutocapitalization() -> some View {
        #if os(iOS)
            return textInputAutocapitalization(.never)
        #else
            return self
        #endif
    }
}
