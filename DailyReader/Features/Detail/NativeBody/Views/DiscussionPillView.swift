import SwiftUI

/// 「查看知乎讨论 / 查看原回答」药丸按钮，靛蓝底色。
struct DiscussionPillView: View {
    let url: String
    let label: String
    var onLinkTap: (URL) -> Void = { _ in }

    var body: some View {
        Button {
            if let u = URL(string: url) { onLinkTap(u) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "bubble.right")
                Text(label)
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(DS.indigo)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(DS.indigo.opacity(0.13))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
