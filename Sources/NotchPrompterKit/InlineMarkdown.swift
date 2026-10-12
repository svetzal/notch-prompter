import Foundation

/// Removes inline Markdown markup, leaving the words a presenter reads.
enum InlineMarkdown {

    /// Plain, whitespace-collapsed text with inline markup removed.
    static func plainText(_ markdown: String) -> String {
        var cleaner = Cleaner(Array(markdown))
        let text = cleaner.run()
        return decodingEntities(Words.split(text).joined(separator: " "))
    }

    private static let entities: [(String, String)] = [
        ("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"),
        ("&quot;", "\""), ("&#39;", "'"), ("&amp;", "&")
    ]

    static func decodingEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        return entities.reduce(text) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
    }

    /// A single left-to-right pass over the characters of one paragraph.
    private struct Cleaner {
        let chars: [Character]
        var index = 0
        var output = ""

        init(_ chars: [Character]) {
            self.chars = chars
        }

        mutating func run() -> String {
            while index < chars.count {
                step()
            }
            return output
        }

        private mutating func step() {
            switch chars[index] {
            case "\\": consumeEscape()
            case "!": consumeImage()
            case "[": consumeLink()
            case "*", "`", "~", "_": consumeEmphasis()
            case "<": consumeAngleBracket()
            default: emit(chars[index])
            }
        }

        private mutating func consumeEscape() {
            guard let next = peek(1), next.isPunctuationOrSymbol else {
                emit("\\")
                return
            }
            output.append(next)
            index += 2
        }

        private mutating func consumeImage() {
            guard peek(1) == "[", let end = linkEnd(from: index + 1) else {
                emit("!")
                return
            }
            index = end.next
        }

        private mutating func consumeLink() {
            guard let end = linkEnd(from: index) else {
                emit("[")
                return
            }
            output += InlineMarkdown.plainText(String(chars[(index + 1)..<end.textEnd]))
            index = end.next
        }

        /// Drops `*`, backticks, `~~`, and `_` that is not inside a word.
        private mutating func consumeEmphasis() {
            let char = chars[index]
            if char == "~", peek(1) != "~" {
                emit(char)
            } else if char == "~" {
                index += 2
            } else if char == "_", isIntraword(at: index) {
                emit(char)
            } else {
                index += 1
            }
        }

        private mutating func emit(_ char: Character) {
            output.append(char)
            index += 1
        }

        private func peek(_ offset: Int) -> Character? {
            let target = index + offset
            return target < chars.count ? chars[target] : nil
        }

        private func isIntraword(at position: Int) -> Bool {
            guard position > 0, position + 1 < chars.count else { return false }
            return chars[position - 1].isLetterOrNumber && chars[position + 1].isLetterOrNumber
        }

        /// For `[text](url)` or `[text][ref]` opening at `open`, where the text
        /// ends and where scanning resumes.
        private func linkEnd(from open: Int) -> (textEnd: Int, next: Int)? {
            guard let close = chars[(open + 1)...].firstIndex(of: "]"), close + 1 < chars.count else {
                return nil
            }
            let closer: Character
            switch chars[close + 1] {
            case "(": closer = ")"
            case "[": closer = "]"
            default: return nil
            }
            guard let end = chars[(close + 2)...].firstIndex(of: closer) else { return nil }
            return (close, end + 1)
        }

        /// Autolinks keep their address; HTML tags disappear; a lone `<` stays.
        private mutating func consumeAngleBracket() {
            guard let next = peek(1), next.isLetter || next == "/" || next == "!",
                  let close = chars[(index + 1)...].firstIndex(of: ">") else {
                emit("<")
                return
            }
            let inner = String(chars[(index + 1)..<close])
            guard !inner.contains("<") else {
                emit("<")
                return
            }
            let isAutolink = !inner.contains(" ") && (inner.contains("://") || inner.contains("@"))
            guard isAutolink || Self.isHTMLTag(inner) else {
                emit("<")
                return
            }
            if isAutolink {
                output += inner
            }
            index = close + 1
        }

        /// `br`, `/span`, `img src="x" /`, `!doctype`: a name, then nothing or attributes.
        private static func isHTMLTag(_ inner: String) -> Bool {
            var body = Substring(inner)
            if body.first == "/" || body.first == "!" {
                body = body.dropFirst()
            }
            let name = body.prefix { $0.isLetter || $0.isNumber }
            guard !name.isEmpty else { return false }
            let rest = body.dropFirst(name.count)
            if rest.isEmpty || rest == "/" { return true }
            return rest.first == " " && (rest.contains("=") || rest.trimmingCharacters(in: .whitespaces) == "/")
        }
    }
}

private extension Character {
    var isLetterOrNumber: Bool { isLetter || isNumber }
    var isPunctuationOrSymbol: Bool { isPunctuation || isSymbol }
}
