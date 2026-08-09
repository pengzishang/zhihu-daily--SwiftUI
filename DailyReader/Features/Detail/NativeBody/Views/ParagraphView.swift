import SwiftUI

/// 段落视图，含可选「首字朱砂下沉」（复刻 WebView 的 drop-cap 效果）。
struct ParagraphView: View {
    let nodes: [InlineNode]
    let isFirst: Bool
    let fontSize: Double
    var onLinkTap: (URL) -> Void = { _ in }
    var onAISearch: (String) -> Void = { _ in }

    var body: some View {
        NativeSelectableAttributedText(
            text: makeAttributed(),
            baseFont: .systemFont(ofSize: fontSize),
            textColor: DS.inkUI,
            lineSpacing: fontSize * 0.65,
            emphasis: dropCap,
            onLinkTap: onLinkTap,
            onAISearch: onAISearch
        )
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func makeAttributed() -> AttributedString {
        InlineContentView.build(nodes, baseSize: fontSize)
    }

    private var dropCap: NativeTextEmphasis? {
        guard isFirst else { return nil }
        let plain = inlinePlainText(nodes).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = plain.first else { return nil }
        let firstChar = String(first)
        let isQuestion = firstChar == "Q" || firstChar == "问" || plain.hasPrefix("Q:") || plain.hasPrefix("Q：")
        guard !isQuestion else { return nil }

        return NativeTextEmphasis(
            range: NSRange(location: 0, length: firstChar.utf16.count),
            font: DS.uiSongBlack(fontSize * 3.35),
            color: DS.cinnabarUI
        )
    }
}
