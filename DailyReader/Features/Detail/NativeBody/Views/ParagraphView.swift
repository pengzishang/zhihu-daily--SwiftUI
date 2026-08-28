import SwiftUI

/// 段落视图，含可选「首字朱砂下沉」（复刻 WebView 的 drop-cap 效果）。
struct ParagraphView: View {
    let nodes: [InlineNode]
    let isFirst: Bool
    let fontSize: Double
    var onLinkTap: (URL) -> Void = { _ in }

    var body: some View {
        Text(makeAttributed())
            .font(.system(size: fontSize))
            .foregroundStyle(DS.ink)
            .lineSpacing(fontSize * 0.55)
            .textSelection(.enabled)
            .environment(\.openURL, OpenURLAction { url in
                onLinkTap(url)
                return .handled
            })
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func makeAttributed() -> AttributedString {
        var attr = InlineContentView.build(nodes, baseSize: fontSize)
        guard isFirst else { return attr }

        let plain = inlinePlainText(nodes).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = plain.first else { return attr }
        let firstChar = String(first)
        let isQuestion = firstChar == "Q" || firstChar == "问" || plain.hasPrefix("Q:") || plain.hasPrefix("Q：")
        guard !isQuestion else { return attr }

        // 首字朱砂放大（近似 drop-cap，不在流内浮动）
        let charStart = attr.characters.startIndex
        let charEnd = attr.characters.index(after: charStart)
        let range = charStart..<charEnd
        attr[range].font = DS.songBlack(fontSize * 2.6)
        attr[range].foregroundColor = DS.cinnabar
        return attr
    }
}
