import SwiftUI

/// 小标题（h2 等），宋体加粗，复用「今日刊」刊头气质。
struct HeadingView: View {
    let text: String
    let level: Int
    let fontSize: Double

    var body: some View {
        Text(text)
            .font(DS.songBold(fontSize * (level <= 2 ? 1.3 : 1.15)))
            .foregroundStyle(DS.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 6)
            .textSelection(.enabled)
    }
}
