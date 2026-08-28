import SwiftUI

/// 单个内容块的渲染分发器，供容器与引用块递归复用。
struct BlockRenderer: View {
    let block: ArticleBlock
    let fontSize: Double
    var onImageTap: (String) -> Void = { _ in }
    var onLinkTap: (URL) -> Void = { _ in }

    var body: some View {
        switch block {
        case .paragraph(_, let nodes, let isFirst):
            ParagraphView(nodes: nodes, isFirst: isFirst, fontSize: fontSize, onLinkTap: onLinkTap)
        case .heading(_, let text, let level):
            HeadingView(text: text, level: level, fontSize: fontSize)
        case .image(_, let img):
            FigureView(figure: FigureBlock(image: img, caption: nil), fontSize: fontSize, onImageTap: onImageTap)
        case .figure(_, let figure):
            FigureView(figure: figure, fontSize: fontSize, onImageTap: onImageTap)
        case .blockquote(_, let blocks):
            BlockquoteView(blocks: blocks, fontSize: fontSize, onImageTap: onImageTap, onLinkTap: onLinkTap)
        case .divider:
            Rectangle()
                .fill(DS.hairline)
                .frame(height: 1)
        case .authorMeta(_, let meta):
            AuthorMetaView(meta: meta, fontSize: fontSize, onLinkTap: onLinkTap)
        case .linkCard(_, let card):
            LinkCardView(card: card, fontSize: fontSize, onLinkTap: onLinkTap)
        case .code(_, let code):
            CodeBlockView(code: code, fontSize: fontSize)
        case .discussionPill(_, let url, let label):
            DiscussionPillView(url: url, label: label, onLinkTap: onLinkTap)
        case .rawText(_, let text):
            Text(text)
                .font(.system(size: fontSize, design: .monospaced))
                .foregroundStyle(DS.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }
}

/// 原生正文容器：把解析出的内容块按统一间距/字号纵向排布。
struct NativeBodyView: View {
    let blocks: [ArticleBlock]
    let fontSize: Double
    var onImageTap: (String) -> Void = { _ in }
    var onLinkTap: (URL) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(blocks) { block in
                BlockRenderer(
                    block: block,
                    fontSize: fontSize,
                    onImageTap: onImageTap,
                    onLinkTap: onLinkTap
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
