import Foundation

struct ParseError: Error, Equatable {
    let message: String
}

/// 把知乎日报正文 HTML 解析为 `[ArticleBlock]`。
/// 设计目标：覆盖实测标签集、对脏 HTML 容错、绝不崩溃。
struct HTMLToBlocksParser {
    private let tokens: [HTMLToken]
    private var index = 0
    private var counter = 0
    private var firstContentParagraphAssigned = false

    init(html: String) {
        self.tokens = HTMLTokenizer.tokenize(html)
    }

    mutating func parse() -> Result<[ArticleBlock], ParseError> {
        let blocks = parseBlocks(terminatedBy: nil)
        return .success(blocks)
    }

    // MARK: - 游标

    private mutating func nextID() -> BlockID {
        counter += 1
        return BlockID(value: counter)
    }

    private func peek() -> HTMLToken? {
        guard index < tokens.count else { return nil }
        return tokens[index]
    }

    private mutating func consume() {
        if index < tokens.count { index += 1 }
    }

    // MARK: - 块级解析

    private mutating func parseBlocks(terminatedBy closing: String?) -> [ArticleBlock] {
        var blocks: [ArticleBlock] = []
        var guardCount = 0
        while let tok = peek() {
            guard guardCount < 200_000 else { break }
            guardCount += 1

            switch tok.kind {
            case .text(let s):
                consume()
                let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    let node = InlineNode.text(HTMLEntityDecoder.decode(s))
                    var isFirst = false
                    if !firstContentParagraphAssigned {
                        firstContentParagraphAssigned = true
                        isFirst = true
                    }
                    blocks.append(.paragraph(id: nextID(), nodes: [node], isFirst: isFirst))
                }

            case .open(let name, let attrs):
                switch name {
                case "p":
                    consume()
                    blocks.append(parseParagraph())
                case "h1", "h2", "h3", "h4":
                    consume()
                    let text = inlinePlainText(parseInline(terminatedBy: name))
                    let level = name == "h2" ? 2 : (name == "h3" ? 3 : (name == "h4" ? 4 : 1))
                    blocks.append(.heading(id: nextID(), text: text, level: level))
                case "img":
                    if let img = makeImage(from: attrs) { blocks.append(.image(id: nextID(), img)) }
                    consume()
                case "figure":
                    consume()
                    blocks.append(parseFigure())
                case "blockquote":
                    consume()
                    blocks.append(.blockquote(id: nextID(), blocks: parseBlocks(terminatedBy: "blockquote")))
                case "hr":
                    consume()
                    blocks.append(.divider(id: nextID()))
                case "pre":
                    blocks.append(parsePre())
                case "script", "style":
                    consume()
                    skipUntilClose(name)
                case "div":
                    consume()
                    blocks.append(contentsOf: parseDiv(attrs))
                case "br":
                    consume()
                default:
                    consume()
                    let inner = parseBlocks(terminatedBy: name)
                    blocks.append(contentsOf: inner)
                }

            case .self(let name, let attrs):
                switch name {
                case "img":
                    if let img = makeImage(from: attrs) { blocks.append(.image(id: nextID(), img)) }
                case "hr":
                    blocks.append(.divider(id: nextID()))
                default:
                    break
                }
                consume()

            case .close(let name):
                if let closing, name == closing {
                    consume()
                    return blocks
                } else {
                    consume()
                }
            }
        }
        return blocks
    }

    // MARK: - 段落 / 内联

    private mutating func parseParagraph() -> ArticleBlock {
        let nodes = parseInline(terminatedBy: "p")

        // 检测「查看知乎讨论 / 查看原回答」药丸
        for node in nodes {
            if case .link(let l) = node {
                let labelText = inlinePlainText(l.label)
                if labelText.contains("查看知乎讨论") || labelText.contains("查看原回答") {
                    return .discussionPill(id: nextID(), url: l.url, label: labelText)
                }
            }
        }

        var isFirst = false
        if !firstContentParagraphAssigned {
            firstContentParagraphAssigned = true
            isFirst = true
        }
        return .paragraph(id: nextID(), nodes: nodes, isFirst: isFirst)
    }

    private mutating func parseInline(terminatedBy closing: String?) -> [InlineNode] {
        var nodes: [InlineNode] = []
        var guardCount = 0
        while let tok = peek() {
            guard guardCount < 200_000 else { break }
            guardCount += 1

            switch tok.kind {
            case .text(let s):
                consume()
                let decoded = HTMLEntityDecoder.decode(s)
                if !decoded.isEmpty { nodes.append(.text(decoded)) }

            case .open(let name, let attrs):
                switch name {
                case "strong", "b":
                    consume()
                    nodes.append(.strong(parseInline(terminatedBy: name)))
                case "em", "i":
                    consume()
                    nodes.append(.em(parseInline(terminatedBy: name)))
                case "sup":
                    consume()
                    nodes.append(.sup(parseInline(terminatedBy: name)))
                case "a":
                    consume()
                    nodes.append(parseLink(attrs))
                case "br":
                    consume()
                    nodes.append(.br)
                case "span":
                    consume()
                    nodes.append(.span(className: attrs["class"], parseInline(terminatedBy: name)))
                case "img":
                    consume()
                default:
                    consume()
                    nodes.append(contentsOf: parseInline(terminatedBy: name))
                }

            case .self(let name, _):
                if name == "br" { nodes.append(.br) }
                consume()

            case .close(let name):
                if let closing, name == closing {
                    consume()
                    return nodes
                } else {
                    consume()
                }
            }
        }
        return nodes
    }

    private mutating func parseLink(_ attrs: [String: String]) -> InlineNode {
        let href = HTMLEntityDecoder.decode(attrs["href"] ?? "")
        let cls = attrs["class"] ?? ""
        let isExternal = cls.lowercased().contains("external") || isExternalHost(href)
        let label = parseInline(terminatedBy: "a")
        return .link(LinkInline(url: href, label: label, isExternal: isExternal))
    }

    private func isExternalHost(_ url: String) -> Bool {
        guard let u = URL(string: url), let host = u.host?.lowercased() else { return false }
        return !host.contains("zhihu.com")
    }

    // MARK: - figure / 图片

    private mutating func parseFigure() -> ArticleBlock {
        var image: ImageBlock?
        var caption: String?
        var guardCount = 0
        while let tok = peek() {
            guard guardCount < 50_000 else { break }
            guardCount += 1
            switch tok.kind {
            case .self("img", let a):
                if image == nil { image = makeImage(from: a) }
                consume()
            case .open("img", let a):
                if image == nil { image = makeImage(from: a) }
                consume()
            case .open("figcaption", _):
                consume()
                caption = inlinePlainText(parseInline(terminatedBy: "figcaption"))
            case .close("figure"):
                consume()
                return makeFigure(image: image, caption: caption)
            default:
                consume()
            }
        }
        return makeFigure(image: image, caption: caption)
    }

    private mutating func makeFigure(image: ImageBlock?, caption: String?) -> ArticleBlock {
        if let img = image {
            return .figure(id: nextID(), FigureBlock(image: img, caption: caption?.isEmpty == false ? caption : nil))
        }
        return .divider(id: nextID())
    }

    private func makeImage(from attrs: [String: String]) -> ImageBlock? {
        let url = attrs["data-original"] ?? attrs["src"]
        guard let u = url, !u.isEmpty else { return nil }
        let cls = attrs["class"] ?? ""
        let kind: ImageKind
        if cls.contains("content-image") { kind = .content }
        else if cls.contains("origin_image") { kind = .origin }
        else if cls.contains("ConditionalImagePortal") { kind = .conditional }
        else { kind = .content }
        return ImageBlock(url: u, alt: attrs["alt"], kind: kind)
    }

    // MARK: - div 特例（作者块 / 富链接卡 / 通用容器）

    private mutating func parseDiv(_ attrs: [String: String]) -> [ArticleBlock] {
        let cls = attrs["class"] ?? ""
        if cls.contains("meta") {
            return [parseAuthorMeta()]
        }
        if cls.lowercased().contains("linkcard") {
            return [parseLinkCard(attrs)]
        }
        let inner = parseBlocks(terminatedBy: "div")
        return inner
    }

    private mutating func parseAuthorMeta() -> ArticleBlock {
        var avatarURL: String?
        var author = ""
        var bio: String?
        var guardCount = 0
        metaLoop: while let tok = peek() {
            guard guardCount < 50_000 else { break }
            guardCount += 1
            switch tok.kind {
            case .self("img", let a):
                if (a["class"] ?? "").contains("avatar"), avatarURL == nil {
                    avatarURL = a["data-original"] ?? a["src"]
                }
                consume()
            case .open("img", let a):
                if (a["class"] ?? "").contains("avatar"), avatarURL == nil {
                    avatarURL = a["data-original"] ?? a["src"]
                }
                consume()
            case .open("span", let a):
                let cls = a["class"] ?? ""
                consume()
                let inner = parseInline(terminatedBy: "span")
                if cls.contains("author") {
                    author = inlinePlainText(inner)
                } else if cls.contains("bio") {
                    bio = inlinePlainText(inner)
                }
            case .close("div"):
                consume()
                break metaLoop
            default:
                consume()
            }
        }

        // 紧跟其后的 <a class="originUrl" href="..."> 提供「查看原回答」入口
        var originURL: String?
        if case .open("a", let a) = peek()?.kind, (a["class"] ?? "").contains("originUrl") {
            consume()
            originURL = a["href"]
            skipUntilClose("a")
        }

        return .authorMeta(
            id: nextID(),
            AuthorMetaBlock(
                avatarURL: avatarURL,
                author: author.isEmpty ? "作者" : author,
                bio: bio?.isEmpty == false ? bio : nil,
                originURL: originURL
            )
        )
    }

    private mutating func parseLinkCard(_ attrs: [String: String]) -> ArticleBlock {
        var title = ""
        var description = ""
        var url = attrs["data-url"] ?? ""
        var imageURL: String?
        var guardCount = 0
        while let tok = peek() {
            guard guardCount < 50_000 else { break }
            guardCount += 1
            switch tok.kind {
            case .open("a", let a):
                if url.isEmpty { url = a["href"] ?? "" }
                consume()
                parseLinkCardInside(&title, &description, &imageURL, a)
            case .self("img", let a):
                if imageURL == nil { imageURL = a["data-original"] ?? a["src"] }
                consume()
            case .open("span", _):
                consume()
                let inner = parseInline(terminatedBy: "span")
                extractLinkCardText(inner, title: &title, description: &description)
            case .close("div"):
                consume()
                return makeLinkCard(title: title, description: description, url: url, imageURL: imageURL)
            default:
                consume()
            }
        }
        return makeLinkCard(title: title, description: description, url: url, imageURL: imageURL)
    }

    private mutating func parseLinkCardInside(
        _ title: inout String,
        _ description: inout String,
        _ imageURL: inout String?,
        _ attrs: [String: String]
    ) {
        var guardCount = 0
        while let tok = peek() {
            guard guardCount < 50_000 else { break }
            guardCount += 1
            switch tok.kind {
            case .open("span", _):
                consume()
                let inner = parseInline(terminatedBy: "span")
                extractLinkCardText(inner, title: &title, description: &description)
            case .self("img", let a):
                if imageURL == nil { imageURL = a["data-original"] ?? a["src"] }
            case .close("a"):
                consume()
                return
            default:
                consume()
            }
        }
    }

    /// 从 LinkCard 的内联节点里提取标题 / 描述。
    /// 真实结构里 title 可能直接是 `LinkCard-title`，也可能嵌套在 `LinkCard-contents` 内，
    /// 因此递归处理任意层级的 span。
    private func extractLinkCardText(_ nodes: [InlineNode], title: inout String, description: inout String) {
        for n in nodes {
            switch n {
            case .span(let cls, let children):
                if let c = cls, c.contains("LinkCard-title") {
                    if title.isEmpty { title = inlinePlainText(children) }
                } else if let c = cls, c.contains("LinkCard-desc") {
                    if description.isEmpty { description = inlinePlainText(children) }
                } else {
                    extractLinkCardText(children, title: &title, description: &description)
                }
            default:
                break
            }
        }
    }

    private mutating func makeLinkCard(title: String, description: String, url: String, imageURL: String?) -> ArticleBlock {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = t.isEmpty ? (URL(string: url)?.host ?? "链接") : t
        return .linkCard(
            id: nextID(),
            LinkCardBlock(
                title: finalTitle,
                url: url,
                description: description.isEmpty ? nil : description,
                imageURL: imageURL
            )
        )
    }

    // MARK: - 代码块

    private mutating func parsePre() -> ArticleBlock {
        if case .open("pre", _) = peek()?.kind { consume() }
        var code = ""
        if case .open("code", _) = peek()?.kind { consume() }
        var guardCount = 0
        while let tok = peek() {
            guard guardCount < 50_000 else { break }
            guardCount += 1
            switch tok.kind {
            case .text(let s):
                consume()
                code += s
            case .close("code"):
                consume()
            case .close("pre"):
                consume()
                return .code(id: nextID(), CodeBlock(language: nil, code: code.trimmingCharacters(in: .whitespacesAndNewlines)))
            default:
                consume()
            }
        }
        return .code(id: nextID(), CodeBlock(language: nil, code: code.trimmingCharacters(in: .whitespacesAndNewlines)))
    }

    // MARK: - 跳过辅助

    private mutating func skipUntilClose(_ name: String) {
        var depth = 1
        while let tok = peek() {
            switch tok.kind {
            case .open(let n, _):
                if n == name { depth += 1 }
            case .close(let n):
                if n == name {
                    consume()
                    depth -= 1
                    if depth == 0 { return }
                    continue
                }
            default:
                break
            }
            consume()
        }
    }
}
