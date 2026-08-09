import SwiftUI

/// 小标题（h2 等），宋体加粗，复用「今日刊」刊头气质。
struct HeadingView: View {
    let text: String
    let level: Int
    let fontSize: Double
    var onAISearch: (String) -> Void = { _ in }

    var body: some View {
        NativeSelectableAttributedText(
            text: makeAttributed(),
            baseFont: DS.uiSongBold(fontSize * (level <= 2 ? 1.3 : 1.15)),
            textColor: DS.inkUI,
            lineSpacing: 0,
            emphasis: nil,
            onLinkTap: { _ in },
            onAISearch: onAISearch
        )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 6)
    }

    private func makeAttributed() -> AttributedString {
        var attributed = AttributedString(text)
        attributed.font = DS.songBold(fontSize * (level <= 2 ? 1.3 : 1.15))
        attributed.foregroundColor = DS.ink
        return attributed
    }
}
