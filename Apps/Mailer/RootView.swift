import MailerCore
import SwiftUI

/// アカウント未登録なら onboarding、登録済みなら受信トレイを表示する。
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.accountList.accounts.isEmpty {
                OnboardingView()
            } else {
                NavigationStack {
                    InboxView()
                }
            }
        }
        #if os(macOS)
            .frame(minWidth: 700, minHeight: 480)
        #endif
    }
}
