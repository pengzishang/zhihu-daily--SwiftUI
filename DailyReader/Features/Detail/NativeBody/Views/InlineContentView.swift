import SwiftUI

/// 把行内节点渲染为原生富文本。链接通过 `AttributedString.link` + 环境变量 `openURL` 路由到外部 Safari，与 WebView 行为一致。
struct InlineContentView: View {
    let nodes: [InlineNode]
    let fontSize: Double
    var onLinkTap: (URL) -> Void = { _ in }

    var body: some View {
        Text(Self.build(nodes, baseSize: fontSize))
            .font(.system(size: fontSize))
            .foregroundStyle(DS.ink)
            .lineSpacing(fontSize * 0.5)
            .textSelection(.enabled)
            .environment(\.openURL, OpenURLAction { url in
                onLinkTap(url)
                return .handled
            })
    }

    /// 由行内节点构建 `AttributedString`，供本组件及段落首字下沉复用。
    static func build(_ nodes: [InlineNode], baseSize: Double) -> AttributedString {
        var result = AttributedString()
        for node in nodes {
            switch node {
            case .text(let s):
                result += AttributedString(s)
            case .strong(let children):
                var c = build(children, baseSize: baseSize)
                c.font = .system(size: baseSize, weight: .bold)
                result += c
            case .em(let children):
                var c = build(children, baseSize: baseSize)
                c.font = .system(size: baseSize).italic()
                result += c
            case .sup(let children):
                var c = build(children, baseSize: baseSize)
                c.font = .system(size: baseSize * 0.7)
                c.baselineOffset = baseSize * 0.4
                result += c
            case .link(let link):
                var c = build(link.label, baseSize: baseSize)
                if let url = URL(string: link.url) {
                    c.link = url
                }
                c.foregroundColor = DS.indigo
                result += c
            case .br:
                result += AttributedString("\n")
            case .span(_, let children):
                result += build(children, baseSize: baseSize)
            }
        }
        return result
    }
}
