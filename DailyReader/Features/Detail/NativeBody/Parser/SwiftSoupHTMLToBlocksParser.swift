import Foundation
import SwiftSoup

struct SwiftSoupHTMLToBlocksParser {
    private static let maximumDepth = 64
    private static let maximumVisitedNodes = 10_000

    private let html: String
    private var counter = 0
    private var firstContentParagraphAssigned = false
    private var visitedNodes = 0
    private var hasExceededLimit = false

    init(html: String) {
        self.html = html
    }

    mutating func parse() -> [ArticleBlock]? {
        guard let document = try? SwiftSoup.parseBodyFragment(html),
              let body = document.body() else {
            return nil
        }
        let blocks = parseBlocks(body.getChildNodes())
        return hasExceededLimit ? nil : blocks
    }

    private mutating func parseBlocks(_ nodes: [Node], depth: Int = 0) -> [ArticleBlock] {
        guard allowsDepth(depth) else { return [] }
        var blocks: [ArticleBlock] = []

        for (index, node) in nodes.enumerated() {
            guard registerVisit() else { return [] }
            if let textNode = node as? TextNode {
                let text = textNode.getWholeText()
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    blocks.append(makeParagraph(nodes: [.text(text)]))
                }
                continue
            }

            guard let element = node as? Element else { continue }
            let tag = element.tagNameNormal()

            switch tag {
            case "p":
                blocks.append(makeParagraph(nodes: inlineNodes(from: element.getChildNodes(), depth: depth + 1)))
            case "h1", "h2", "h3", "h4":
                let level = tag == "h2" ? 2 : (tag == "h3" ? 3 : (tag == "h4" ? 4 : 1))
                blocks.append(.heading(id: nextID(), text: Self.text(of: element), level: level))
            case "img":
                if let image = makeImage(from: element) {
                    blocks.append(.image(id: nextID(), image))
                }
            case "figure":
                blocks.append(makeFigure(from: element))
            case "blockquote":
                blocks.append(.blockquote(id: nextID(), blocks: parseBlocks(element.getChildNodes(), depth: depth + 1)))
            case "hr":
                blocks.append(.divider(id: nextID()))
            case "pre":
                blocks.append(.code(
                    id: nextID(),
                    CodeBlock(language: nil, code: Self.text(of: element, preservingWhitespace: true))
                ))
            case "script", "style":
                continue
            case "div":
                let classes = Self.attribute("class", of: element)
                if classes.contains("meta") {
                    let originURL = originURL(after: index, in: nodes)
                    blocks.append(makeAuthorMeta(from: element, originURL: originURL))
                } else if classes.lowercased().contains("linkcard") {
                    blocks.append(makeLinkCard(from: element))
                } else {
                    blocks.append(contentsOf: parseBlocks(element.getChildNodes(), depth: depth + 1))
                }
            case "a" where Self.classesContain("originUrl", in: element):
                continue
            default:
                blocks.append(contentsOf: parseBlocks(element.getChildNodes(), depth: depth + 1))
            }
        }

        return blocks
    }

    private mutating func makeParagraph(nodes: [InlineNode]) -> ArticleBlock {
        for node in nodes {
            if case .link(let link) = node {
                let label = inlinePlainText(link.label)
                if label.contains("查看知乎讨论") || label.contains("查看原回答") {
                    return .discussionPill(id: nextID(), url: link.url, label: label)
                }
            }
        }

        let isFirst = !firstContentParagraphAssigned
        firstContentParagraphAssigned = true
        return .paragraph(id: nextID(), nodes: nodes, isFirst: isFirst)
    }

    private mutating func inlineNodes(from nodes: [Node], depth: Int) -> [InlineNode] {
        guard allowsDepth(depth) else { return [] }
        var result: [InlineNode] = []

        for node in nodes {
            guard registerVisit() else { return [] }
            if let textNode = node as? TextNode {
                let text = textNode.getWholeText()
                if !text.isEmpty { result.append(.text(text)) }
                continue
            }

            guard let element = node as? Element else { continue }
            let children = inlineNodes(from: element.getChildNodes(), depth: depth + 1)
            switch element.tagNameNormal() {
            case "strong", "b":
                result.append(.strong(children))
            case "em", "i":
                result.append(.em(children))
            case "sup":
                result.append(.sup(children))
            case "a":
                let url = Self.attribute("href", of: element)
                let classes = Self.attribute("class", of: element).lowercased()
                if Self.isWebURL(url) {
                    result.append(.link(LinkInline(
                        url: url,
                        label: children,
                        isExternal: classes.contains("external") || Self.isExternalHost(url)
                    )))
                } else {
                    result.append(contentsOf: children)
                }
            case "br":
                result.append(.br)
            case "span":
                result.append(.span(className: Self.nonEmptyAttribute("class", of: element), children))
            case "img":
                continue
            default:
                result.append(contentsOf: children)
            }
        }

        return result
    }

    private mutating func makeFigure(from element: Element) -> ArticleBlock {
        guard let imageElement = firstDescendant(in: element, where: { $0.tagNameNormal() == "img" }),
              let image = makeImage(from: imageElement) else {
            return .divider(id: nextID())
        }
        let caption = firstDescendant(in: element, where: { $0.tagNameNormal() == "figcaption" })
            .map { Self.text(of: $0) }
        return .figure(id: nextID(), FigureBlock(image: image, caption: caption?.isEmpty == false ? caption : nil))
    }

    private func makeImage(from element: Element) -> ImageBlock? {
        guard let url = Self.nonEmptyAttribute("data-original", of: element) ?? Self.nonEmptyAttribute("src", of: element) else {
            return nil
        }
        let classes = Self.attribute("class", of: element)
        let kind: ImageKind
        if classes.contains("content-image") {
            kind = .content
        } else if classes.contains("origin_image") {
            kind = .origin
        } else if classes.contains("ConditionalImagePortal") {
            kind = .conditional
        } else {
            kind = .content
        }
        return ImageBlock(url: url, alt: Self.nonEmptyAttribute("alt", of: element), kind: kind)
    }

    private mutating func makeAuthorMeta(from element: Element, originURL: String?) -> ArticleBlock {
        let avatarURL = firstDescendant(in: element) { Self.classesContain("avatar", in: $0) }
            .flatMap { Self.nonEmptyAttribute("data-original", of: $0) ?? Self.nonEmptyAttribute("src", of: $0) }
        let author = firstDescendant(in: element) { Self.classesContain("author", in: $0) }
            .map { Self.text(of: $0) }
        let bio = firstDescendant(in: element) { Self.classesContain("bio", in: $0) }
            .map { Self.text(of: $0) }

        return .authorMeta(
            id: nextID(),
            AuthorMetaBlock(
                avatarURL: avatarURL,
                author: author?.isEmpty == false ? author! : "作者",
                bio: bio?.isEmpty == false ? bio : nil,
                originURL: originURL
            )
        )
    }

    private mutating func makeLinkCard(from element: Element) -> ArticleBlock {
        let link = firstDescendant(in: element, where: { $0.tagNameNormal() == "a" })
        let candidateURL = Self.nonEmptyAttribute("data-url", of: element) ?? link.flatMap { Self.nonEmptyAttribute("href", of: $0) } ?? ""
        let url = Self.isWebURL(candidateURL) ? candidateURL : ""
        let title = firstDescendant(in: element) { Self.classesContain("LinkCard-title", in: $0) }
            .map { Self.text(of: $0) }
        let description = firstDescendant(in: element) { Self.classesContain("LinkCard-desc", in: $0) }
            .map { Self.text(of: $0) }
        let imageURL = firstDescendant(in: element, where: { $0.tagNameNormal() == "img" })
            .flatMap { Self.nonEmptyAttribute("data-original", of: $0) ?? Self.nonEmptyAttribute("src", of: $0) }
        let fallbackTitle = URL(string: url)?.host ?? "链接"

        return .linkCard(
            id: nextID(),
            LinkCardBlock(
                title: title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? title! : fallbackTitle,
                url: url,
                description: description?.isEmpty == false ? description : nil,
                imageURL: imageURL
            )
        )
    }

    private mutating func firstDescendant(
        in element: Element,
        where predicate: (Element) -> Bool
    ) -> Element? {
        var stack = Array(element.getChildNodes().reversed())
        while let node = stack.popLast() {
            guard registerVisit() else { return nil }
            guard let candidate = node as? Element else { continue }
            if predicate(candidate) { return candidate }
            stack.append(contentsOf: candidate.getChildNodes().reversed())
        }
        return nil
    }

    private static func attribute(_ name: String, of element: Element) -> String {
        (try? element.attr(name)) ?? ""
    }

    private static func nonEmptyAttribute(_ name: String, of element: Element) -> String? {
        let value = attribute(name, of: element)
        return value.isEmpty ? nil : value
    }

    private static func text(of element: Element, preservingWhitespace: Bool = false) -> String {
        (try? element.text(trimAndNormaliseWhitespace: !preservingWhitespace)) ?? ""
    }

    private func originURL(after index: Int, in nodes: [Node]) -> String? {
        for node in nodes.dropFirst(index + 1) {
            if let textNode = node as? TextNode,
               textNode.getWholeText().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                continue
            }
            guard let element = node as? Element,
                  element.tagNameNormal() == "a",
                  Self.classesContain("originUrl", in: element),
                  let url = Self.nonEmptyAttribute("href", of: element),
                  Self.isWebURL(url) else {
                return nil
            }
            return url
        }
        return nil
    }

    private static func classesContain(_ value: String, in element: Element) -> Bool {
        attribute("class", of: element).contains(value)
    }

    private static func isWebURL(_ value: String) -> Bool {
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased(), url.host != nil else {
            return false
        }
        return scheme == "http" || scheme == "https"
    }

    private static func isExternalHost(_ url: String) -> Bool {
        guard let url = URL(string: url), let host = url.host?.lowercased() else { return false }
        return !host.contains("zhihu.com")
    }

    private mutating func allowsDepth(_ depth: Int) -> Bool {
        guard depth <= Self.maximumDepth else {
            hasExceededLimit = true
            return false
        }
        return true
    }

    private mutating func registerVisit() -> Bool {
        visitedNodes += 1
        guard visitedNodes <= Self.maximumVisitedNodes else {
            hasExceededLimit = true
            return false
        }
        return true
    }

    private mutating func nextID() -> BlockID {
        counter += 1
        return BlockID(value: counter)
    }
}
