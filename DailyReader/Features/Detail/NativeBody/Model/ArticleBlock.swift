import Foundation

// MARK: - 内容块模型（路线 B：HTML → 原生 SwiftUI）

/// 块级标识符，用于 `Identifiable` 与稳定 diff。
struct BlockID: Hashable {
    let value: Int
}

/// 图片种类，由知乎正文的 class 判定。
enum ImageKind: String, Equatable {
    case content        // content-image
    case origin         // origin_image
    case conditional    // RichText-ConditionalImagePortal
}

struct ImageBlock: Equatable {
    let url: String
    let alt: String?
    let kind: ImageKind
}

struct FigureBlock: Equatable {
    let image: ImageBlock
    let caption: String?
}

struct AuthorMetaBlock: Equatable {
    let avatarURL: String?
    let author: String
    let bio: String?
    let originURL: String?
}

struct LinkCardBlock: Equatable {
    let title: String
    let url: String
    let description: String?
    let imageURL: String?
}

struct CodeBlock: Equatable {
    let language: String?
    let code: String
}

struct LinkInline: Equatable {
    let url: String
    let label: [InlineNode]
    let isExternal: Bool
}

/// 行内节点（段落 / 引用 / 链接卡标题等内部使用）。
indirect enum InlineNode: Equatable {
    case text(String)
    case strong([InlineNode])
    case em([InlineNode])
    case sup([InlineNode])
    case link(LinkInline)
    case br
    case span(className: String?, [InlineNode])
}

/// 文章正文内容块。HTML 解析后全部映射到这一组枚举。
indirect enum ArticleBlock: Identifiable, Equatable {
    case paragraph(id: BlockID, nodes: [InlineNode], isFirst: Bool)
    case heading(id: BlockID, text: String, level: Int)
    case image(id: BlockID, ImageBlock)
    case figure(id: BlockID, FigureBlock)
    case blockquote(id: BlockID, blocks: [ArticleBlock])
    case divider(id: BlockID)
    case authorMeta(id: BlockID, AuthorMetaBlock)
    case linkCard(id: BlockID, LinkCardBlock)
    case code(id: BlockID, CodeBlock)
    case discussionPill(id: BlockID, url: String, label: String)
    case rawText(id: BlockID, String)

    var id: BlockID {
        switch self {
        case .paragraph(let id, _, _): return id
        case .heading(let id, _, _): return id
        case .image(let id, _): return id
        case .figure(let id, _): return id
        case .blockquote(let id, _): return id
        case .divider(let id): return id
        case .authorMeta(let id, _): return id
        case .linkCard(let id, _): return id
        case .code(let id, _): return id
        case .discussionPill(let id, _, _): return id
        case .rawText(let id, _): return id
        }
    }
}

// MARK: - 内联纯文本提取（供 AI 上下文 / 调试）

/// 把行内节点展平为纯文本（去链接符号、去 markdown），用于 AI 上下文与对照。
func inlinePlainText(_ nodes: [InlineNode]) -> String {
    nodes.map { node in
        switch node {
        case .text(let s): return s
        case .strong(let c): return inlinePlainText(c)
        case .em(let c): return inlinePlainText(c)
        case .sup(let c): return inlinePlainText(c)
        case .link(let l): return inlinePlainText(l.label)
        case .br: return " "
        case .span(_, let c): return inlinePlainText(c)
        }
    }.joined()
}
