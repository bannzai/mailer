import SwiftUI

/// メールアドレスから決定的に導出するアカウント識別色。
/// Swift の hashValue はプロセスごとにシードが変わるため、安定した FNV-1a ハッシュで色相を決める。
func accountColor(for email: String) -> Color {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in email.utf8 {
        hash ^= UInt64(byte)
        hash = hash &* 0x100_0000_01b3
    }
    return Color(
        hue: Double(hash % 360) / 360,
        saturation: 0.55,
        brightness: 0.85
    )
}

/// アカウントの視覚識別バッジ。識別色の円 + メールアドレスの頭文字。
struct AccountBadge: View {
    let email: String
    var size: CGFloat = 28

    var body: some View {
        Circle()
            .fill(accountColor(for: email))
            .frame(width: size, height: size)
            .overlay {
                Text(email.prefix(1).uppercased())
                    .font(.system(size: size * 0.5, weight: .bold))
                    .foregroundStyle(.white)
            }
    }
}
