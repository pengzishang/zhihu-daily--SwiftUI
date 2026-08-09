import SwiftUI

/// 代码块：等宽字体 + 横向滚动 + 纸面浮层。
struct CodeBlockView: View {
    let code: CodeBlock
    let fontSize: Double
    var onAISearch: (String) -> Void = { _ in }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            NativeSelectableAttributedText(
                text: makeAttributed(),
                baseFont: .monospacedSystemFont(ofSize: fontSize * 0.85, weight: .regular),
                textColor: DS.inkUI,
                lineSpacing: fontSize * 0.3,
                emphasis: nil,
                onLinkTap: { _ in },
                onAISearch: onAISearch
            )
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(DS.paperElevated)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(DS.hairline, lineWidth: 0.7)
        )
    }

    private func makeAttributed() -> AttributedString {
        var attributed = AttributedString(code.code)
        attributed.font = .system(size: fontSize * 0.85, design: .monospaced)
        attributed.foregroundColor = DS.ink
        return attributed
    }
}
