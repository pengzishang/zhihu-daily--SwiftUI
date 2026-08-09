import Foundation
import SwiftSoup

struct SwiftSoupHTMLToBlocksParser {
    private let html: String
    private var counter = 0
    private var firstContentParagraphAssigned = false

    init(html: String) {
        self.html = html
    }

    mutating func parse() -> [ArticleBlock]? {
        guard let document = try? SwiftSoup.parseBodyFragment(html),
              let body = document.body() else {
            return nil
        }
        return parseBlocks(body.getChildNodes())
    }

    private mutating func parseBlocks(_ nodes: [Node]) -> [ArticleBlock] {
        var blocks: [ArticleBlock] = []

        for (index, node) in nodes.enumerated() {
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
                blocks.append(makeParagraph(nodes: inlineNodes(from: element.getChildNodes())))
            case "h1", "h2", "h3", "h4":
                let level = tag == "h2" ? 2 : (tag == "h3" ? 3 : (tag == "h4" ? 4 : 1))
                blocks.append(.heading(id: nextID(), text: text(of: element), level: level))
            case "img":
                if let image = makeImage(from: element) {
                    blocks.append(.image(id: nextID(), image))
                }
            case "figure":
                blocks.append(makeFigure(from: element))
            case "blockquote":
                blocks.append(.blockquote(id: nextID(), blocks: parseBlocks(element.getChildNodes())))
            case "hr":
                blocks.append(.divider(id: nextID()))
            case "pre":
                blocks.append(.code(
                    id: nextID(),
                    CodeBlock(language: nil, code: text(of: element, preservingWhitespace: true))
                ))
            case "script", "style":
                continue
            case "div":
                let classes = attribute("class", of: element)
                if classes.contains("meta") {
                    let originURL = nodes.dropFirst(index + 1)
                        .compactMap { $0 as? Element }
                        .first(where: { attribute("class", of: $0).contains("originUrl") })
                        .flatMap { nonEmptyAttribute("href", of: $0) }
                    blocks.append(makeAuthorMeta(from: element, originURL: originURL))
                } else if classes.lowercased().contains("linkcard") {
                    blocks.append(makeLinkCard(from: element))
                } else {
                    blocks.append(contentsOf: parseBlocks(element.getChildNodes()))
                }
            default:
                blocks.append(contentsOf: parseBlocks(element.getChildNodes()))
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

    private func inlineNodes(from nodes: [Node]) -> [InlineNode] {
        nodes.flatMap { node -> [InlineNode] in
            if let textNode = node as? TextNode {
                let text = textNode.getWholeText()
                return text.isEmpty ? [] : [.text(text)]
            }

            guard let element = node as? Element else { return [] }
            let children = inlineNodes(from: element.getChildNodes())
            switch element.tagNameNormal() {
            case "strong", "b":
                return [.strong(children)]
            case "em", "i":
                return [.em(children)]
            case "sup":
                return [.sup(children)]
            case "a":
                let url = attribute("href", of: element)
                let classes = attribute("class", of: element).lowercased()
                return [.link(LinkInline(
                    url: url,
                    label: children,
                    isExternal: classes.contains("external") || isExternalHost(url)
                ))]
            case "br":
                return [.br]
            case "span":
                return [.span(className: nonEmptyAttribute("class", of: element), children)]
            case "img":
                return []
            default:
                return children
            }
        }
    }

    private mutating func makeFigure(from element: Element) -> ArticleBlock {
        guard let imageElement = firstDescendant(in: element, where: { $0.tagNameNormal() == "img" }),
              let image = makeImage(from: imageElement) else {
            return .divider(id: nextID())
        }
        let caption = firstDescendant(in: element, where: { $0.tagNameNormal() == "figcaption" })
            .map { text(of: $0) }
        return .figure(id: nextID(), FigureBlock(image: image, caption: caption?.isEmpty == false ? caption : nil))
    }

    private func makeImage(from element: Element) -> ImageBlock? {
        guard let url = nonEmptyAttribute("data-original", of: element) ?? nonEmptyAttribute("src", of: element) else {
            return nil
        }
        let classes = attribute("class", of: element)
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
        return ImageBlock(url: url, alt: nonEmptyAttribute("alt", of: element), kind: kind)
    }

    private mutating func makeAuthorMeta(from element: Element, originURL: String?) -> ArticleBlock {
        let avatarURL = firstDescendant(in: element) { attribute("class", of: $0).contains("avatar") }
            .flatMap { nonEmptyAttribute("data-original", of: $0) ?? nonEmptyAttribute("src", of: $0) }
        let author = firstDescendant(in: element) { attribute("class", of: $0).contains("author") }
            .map { text(of: $0) }
        let bio = firstDescendant(in: element) { attribute("class", of: $0).contains("bio") }
            .map { text(of: $0) }

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
        let url = nonEmptyAttribute("data-url", of: element) ?? link.flatMap { nonEmptyAttribute("href", of: $0) } ?? ""
        let title = firstDescendant(in: element) { attribute("class", of: $0).contains("LinkCard-title") }
            .map { text(of: $0) }
        let description = firstDescendant(in: element) { attribute("class", of: $0).contains("LinkCard-desc") }
            .map { text(of: $0) }
        let imageURL = firstDescendant(in: element, where: { $0.tagNameNormal() == "img" })
            .flatMap { nonEmptyAttribute("data-original", of: $0) ?? nonEmptyAttribute("src", of: $0) }
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

    private func firstDescendant(
        in element: Element,
        where predicate: (Element) -> Bool
    ) -> Element? {
        var stack = Array(element.getChildNodes().reversed())
        while let node = stack.popLast() {
            guard let candidate = node as? Element else { continue }
            if predicate(candidate) { return candidate }
            stack.append(contentsOf: candidate.getChildNodes().reversed())
        }
        return nil
    }

    private func attribute(_ name: String, of element: Element) -> String {
        (try? element.attr(name)) ?? ""
    }

    private func nonEmptyAttribute(_ name: String, of element: Element) -> String? {
        let value = attribute(name, of: element)
        return value.isEmpty ? nil : value
    }

    private func text(of element: Element, preservingWhitespace: Bool = false) -> String {
        (try? element.text(trimAndNormaliseWhitespace: !preservingWhitespace)) ?? ""
    }

    private func isExternalHost(_ url: String) -> Bool {
        guard let url = URL(string: url), let host = url.host?.lowercased() else { return false }
        return !host.contains("zhihu.com")
    }

    private mutating func nextID() -> BlockID {
        counter += 1
        return BlockID(value: counter)
    }
}
