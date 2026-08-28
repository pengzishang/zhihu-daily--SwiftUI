import Foundation

/// HTML 实体解码：覆盖知乎正文出现的命名实体与十进制/十六进制实体。
enum HTMLEntityDecoder {
    static func decode(_ input: String) -> String {
        var result = ""
        var i = input.startIndex
        let end = input.endIndex
        while i < end {
            if input[i] == "&" {
                if let semi = input[i..<end].firstIndex(of: ";"), semi > i {
                    let entity = String(input[input.index(after: i)..<semi])
                    if let decoded = decodeEntity(entity) {
                        result.append(decoded)
                        i = input.index(after: semi)
                        continue
                    }
                }
                // 非合法实体：保留原样
                result.append("&")
                i = input.index(after: i)
            } else {
                result.append(input[i])
                i = input.index(after: i)
            }
        }
        return result
    }

    private static func decodeEntity(_ entity: String) -> String? {
        switch entity {
        case "amp": return "&"
        case "lt": return "<"
        case "gt": return ">"
        case "quot": return "\""
        case "apos", "#39": return "'"
        case "nbsp": return "\u{00A0}"
        case "copy": return "©"
        case "reg": return "®"
        case "hellip": return "…"
        case "mdash": return "—"
        case "ndash": return "–"
        case "ldquo": return "“"
        case "rdquo": return "”"
        case "lsquo": return "‘"
        case "rsquo": return "’"
        case "middot": return "·"
        default:
            if entity.hasPrefix("#") {
                let numPart = String(entity.dropFirst())
                if let scalar = parseNumericEntity(numPart) {
                    return String(scalar)
                }
            }
            return nil
        }
    }

    private static func parseNumericEntity(_ part: String) -> UnicodeScalar? {
        if part.hasPrefix("x") || part.hasPrefix("X") {
            let hex = String(part.dropFirst())
            if let code = UInt32(hex, radix: 16) {
                return UnicodeScalar(code)
            }
        } else if let code = Int(part) {
            if let scalar = UnicodeScalar(code) {
                return scalar
            }
        }
        return nil
    }
}
