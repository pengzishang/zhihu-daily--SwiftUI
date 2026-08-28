import SwiftUI

/// 代码块：等宽字体 + 横向滚动 + 纸面浮层。
struct CodeBlockView: View {
    let code: CodeBlock
    let fontSize: Double

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(code.code)
                .font(.system(size: fontSize * 0.85, design: .monospaced))
                .foregroundStyle(DS.ink)
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
}
