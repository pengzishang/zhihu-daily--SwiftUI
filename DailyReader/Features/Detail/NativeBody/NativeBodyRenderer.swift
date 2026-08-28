import SwiftUI

/// 原生正文渲染编排：
/// - 解析 HTML → `[ArticleBlock]`（带按原文缓存）
/// - 解析失败 / 空时回退到传入的 WebView，保证零回归
/// - 提供纯文本展平，替代 WebView 的 JS 桥 `articleTextPrepared`
enum NativeBodyRenderer {
    private static var cache: [String: [ArticleBlock]] = [:]

    /// 同步解析（供 AI 上下文纯文本使用），空/纯空白 HTML 或无块时返回 nil。
    static func parsedBlocks(html: String) -> [ArticleBlock]? {
        let key = html
        if let cached = cache[key] { return cached }
        var parser = HTMLToBlocksParser(html: html)
        guard case .success(let blocks) = parser.parse(), !blocks.isEmpty else { return nil }
        cache[key] = blocks
        return blocks
    }

    /// 返回原生正文视图；任何异常都回退到 `fallback`（WebView）。
    static func bodyView(
        html: String,
        cssLinks: [String],
        fontSize: Double = 16,
        onImageTap: @escaping (String) -> Void,
        onLinkTap: @escaping (URL) -> Void,
        fallback: @escaping () -> AnyView
    ) -> AnyView {
        guard !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return fallback()
        }
        guard let blocks = parsedBlocks(html: html), !blocks.isEmpty else {
            return fallback()
        }
        return AnyView(
            NativeBodyView(
                blocks: blocks,
                fontSize: fontSize,
                onImageTap: onImageTap,
                onLinkTap: onLinkTap
            )
        )
    }

    /// 把内容块展平为纯文本（去 markdown / 链接符号），供 AI 上下文。
    static func plainText(from blocks: [ArticleBlock]) -> String {
        blocks.map { plainText($0) }.joined(separator: "\n\n")
    }

    private static func plainText(_ b: ArticleBlock) -> String {
        switch b {
        case .paragraph(_, let nodes, _): return inlinePlainText(nodes)
        case .heading(_, let text, _): return text
        case .image: return ""
        case .figure(_, let f): return f.caption ?? ""
        case .blockquote(_, let bs): return bs.map { plainText($0) }.joined(separator: "\n")
        case .divider: return ""
        case .authorMeta(_, let m): return [m.author, m.bio].compactMap { $0 }.joined(separator: " ")
        case .linkCard(_, let c): return [c.title, c.description].compactMap { $0 }.joined(separator: " ")
        case .code(_, let c): return c.code
        case .discussionPill(_, _, let label): return label
        case .rawText(_, let s): return s
        }
    }
}
