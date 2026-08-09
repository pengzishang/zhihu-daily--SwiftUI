import SwiftUI

/// 原生正文渲染编排：
/// - 解析 HTML → `[ArticleBlock]`（带按原文缓存）
/// - 解析失败 / 空时回退到传入的 WebView，保证零回归
/// - 提供纯文本展平，替代 WebView 的 JS 桥 `articleTextPrepared`
enum NativeBodyRenderer {
    private static let cache = NativeBodyParseCache()
    fileprivate static let maximumNativeBlockCount = 800
    fileprivate static let maximumNativeHTMLLength = 120_000

    static func parsedBlocks(html: String) -> [ArticleBlock]? {
        var parser = HTMLToBlocksParser(html: html)
        guard case .success(let blocks) = parser.parse(), !blocks.isEmpty else { return nil }
        return blocks
    }

    static func backgroundBlocks(html: String) async -> [ArticleBlock]? {
        await cache.blocks(for: html)
    }

    /// 返回原生正文视图；任何异常都回退到 `fallback`（WebView）。
    static func bodyView(
        html: String,
        cssLinks: [String],
        fontSize: Double = 16,
        onImageTap: @escaping (String) -> Void,
        onLinkTap: @escaping (URL) -> Void,
        onPreparedText: @escaping (String) -> Void = { _ in },
        fallback: @escaping () -> AnyView
    ) -> AnyView {
        guard !html.isEmpty else {
            return fallback()
        }
        return AnyView(
            DeferredNativeBodyView(
                html: html,
                fontSize: fontSize,
                onImageTap: onImageTap,
                onLinkTap: onLinkTap,
                onPreparedText: onPreparedText,
                fallback: fallback
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

private actor NativeBodyParseCache {
    private var entries: [String: [ArticleBlock]] = [:]

    func blocks(for html: String) -> [ArticleBlock]? {
        guard html.utf8.count <= NativeBodyRenderer.maximumNativeHTMLLength else { return nil }
        if let cached = entries[html] { return cached }
        guard let parsed = NativeBodyRenderer.parsedBlocks(html: html) else { return nil }
        guard parsed.count <= NativeBodyRenderer.maximumNativeBlockCount else { return nil }
        entries[html] = parsed
        return parsed
    }
}

private struct DeferredNativeBodyView: View {
    private enum Phase {
        case loading
        case rendered([ArticleBlock])
        case fallback
    }

    let html: String
    let fontSize: Double
    let onImageTap: (String) -> Void
    let onLinkTap: (URL) -> Void
    let onPreparedText: (String) -> Void
    let fallback: () -> AnyView

    @State private var phase: Phase = .loading

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 240)
            case .fallback:
                fallback()
            case .rendered(let blocks):
                NativeBodyView(
                    blocks: blocks,
                    fontSize: fontSize,
                    onImageTap: onImageTap,
                    onLinkTap: onLinkTap
                )
                .onAppear {
                    onPreparedText(NativeBodyRenderer.plainText(from: blocks))
                }
            }
        }
        .task(id: html) {
            phase = .loading
            let blocks = await NativeBodyRenderer.backgroundBlocks(html: html)
            guard !Task.isCancelled else { return }
            phase = blocks.map(Phase.rendered) ?? .fallback
        }
    }
}
