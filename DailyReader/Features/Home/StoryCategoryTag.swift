import SwiftUI

/// 行内 AI 类目胶囊：小号圆角胶囊，弱化「其他」兜底类。
struct StoryCategoryTag: View {
    let categoryName: String
    let isOther: Bool

    var body: some View {
        Text(categoryName)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(isOther ? DS.inkSecondary.opacity(0.7) : DS.indigo)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(DS.paperElevated)
            )
            .overlay(
                Capsule()
                    .strokeBorder(isOther ? DS.hairline : DS.indigo.opacity(0.45), lineWidth: 0.7)
            )
            .accessibilityLabel("类目：\(categoryName)")
    }
}
