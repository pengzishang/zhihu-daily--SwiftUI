import Foundation

/// 容错 HTML 分词器：把脏 HTML 切成 文本 / 开标签 / 闭标签 / 自闭合标签 四类 token。
/// 不做良构性校验（知乎正文常有未闭合标签、裸 `&`、void 元素不自闭），由上层解析器做栈式收尾。
struct HTMLToken {
    enum Kind {
        case text(String)
        case open(name: String, attrs: [String: String])
        case close(name: String)
        case `self`(name: String, attrs: [String: String])
    }
    let kind: Kind
}

struct HTMLTokenizer {
    /// HTML void 元素：无子节点、无独立闭标签。
    static let voidTags: Set<String> = [
        "br", "img", "hr", "input", "meta", "link",
        "source", "area", "base", "col", "embed", "param", "track", "wbr"
    ]

    static func tokenize(_ html: String) -> [HTMLToken] {
        var tokens: [HTMLToken] = []
        var i = html.startIndex
        let end = html.endIndex
        var textStart = i

        while i < end {
            let c = html[i]
            if c == "<" {
                if textStart < i {
                    tokens.append(HTMLToken(kind: .text(String(html[textStart..<i]))))
                }
                let tagEnd = html[i..<end].firstIndex(of: ">") ?? end
                let tagContent = String(html[html.index(after: i)..<tagEnd])
                if tagContent.hasPrefix("/") {
                    let name = String(tagContent.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
                    tokens.append(HTMLToken(kind: .close(name: name.lowercased())))
                } else {
                    let (name, attrs, selfClosing) = parseTag(tagContent)
                    let lower = name.lowercased()
                    if selfClosing || voidTags.contains(lower) {
                        tokens.append(HTMLToken(kind: .self(name: lower, attrs: attrs)))
                    } else {
                        tokens.append(HTMLToken(kind: .open(name: lower, attrs: attrs)))
                    }
                }
                i = html.index(after: tagEnd)
                textStart = i
            } else {
                i = html.index(after: i)
            }
        }
        if textStart < end {
            tokens.append(HTMLToken(kind: .text(String(html[textStart..<end]))))
        }
        return tokens
    }

    /// 解析单个标签内容（不含外层尖括号），返回 (标签名, 属性字典, 是否自闭合)。
    private static func parseTag(_ content: String) -> (name: String, attrs: [String: String], selfClosing: Bool) {
        var selfClosing = false
        var working = content
        if working.hasSuffix("/") {
            selfClosing = true
            working = String(working.dropLast())
        }

        var scanner = working[...]
        guard let nameEnd = scanner.firstIndex(where: { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" }) else {
            return (String(scanner).trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), [:], selfClosing)
        }
        let rawName = String(scanner[..<nameEnd])
        scanner = scanner[nameEnd...]

        var attrs: [String: String] = [:]
        while !scanner.isEmpty {
            while let first = scanner.first, first == " " || first == "\t" || first == "\n" || first == "\r" {
                scanner = scanner.dropFirst()
            }
            if scanner.isEmpty { break }

            var attrName = ""
            while let first = scanner.first, !first.isWhitespace, first != "=", first != "/" {
                attrName.append(first)
                scanner = scanner.dropFirst()
            }
            while let first = scanner.first, first == " " || first == "\t" {
                scanner = scanner.dropFirst()
            }

            var value = ""
            if scanner.first == "=" {
                scanner = scanner.dropFirst()
                while let first = scanner.first, first == " " || first == "\t" {
                    scanner = scanner.dropFirst()
                }
                if scanner.first == "\"" || scanner.first == "'" {
                    let quote = scanner.first!
                    scanner = scanner.dropFirst()
                    while let first = scanner.first, first != quote {
                        value.append(first)
                        scanner = scanner.dropFirst()
                    }
                    if scanner.first == quote { scanner = scanner.dropFirst() }
                } else {
                    while let first = scanner.first, !first.isWhitespace, first != "/" {
                        value.append(first)
                        scanner = scanner.dropFirst()
                    }
                }
            }
            let key = attrName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty {
                attrs[key] = HTMLEntityDecoder.decode(value)
            }
        }
        return (rawName.lowercased(), attrs, selfClosing)
    }
}
