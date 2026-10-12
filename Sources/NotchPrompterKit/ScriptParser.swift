import Foundation

/// Turns a Markdown script into prompter blocks.
///
/// The goal is readable text, not a faithful Markdown renderer:
///
/// - Paragraphs are separated by blank lines. Soft line breaks inside a
///   paragraph join with a space.
/// - Each list item becomes its own paragraph, without its marker.
/// - Headings (ATX `#` and setext underlines) become notes: visible to the
///   presenter, not timed as speech.
/// - Emphasis, code, link, and image markup is removed. Link text stays; images
///   are dropped. Blockquote markers and code fences are removed and their
///   text kept.
/// - HTML comments (`<!-- … -->`) are removed entirely. They are the place for
///   remarks the presenter should never see.
/// - YAML front matter at the top of the file is ignored.
/// - Cues, anywhere in a paragraph, split it: `[pause]` holds for
///   ``defaultPause`` seconds, `[pause 3]` or `[pause 1.5s]` for that long, and
///   `[note: smile]` shows a note.
public enum ScriptParser {

    /// The hold for a bare `[pause]` cue.
    public static let defaultPause: TimeInterval = 2

    public static func blocks(from markdown: String) -> [PrompterBlock] {
        let normalized = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = droppingFrontMatter(removingHTMLComments(normalized).components(separatedBy: "\n"))

        return BlockScanner.scan(lines).flatMap { raw -> [PrompterBlock] in
            switch raw {
            case .heading(let text):
                let clean = InlineMarkdown.plainText(text)
                return clean.isEmpty ? [] : [.note(clean)]
            case .paragraph(let lines):
                return Cues.split(lines.joined(separator: " "))
            }
        }
    }

    static func removingHTMLComments(_ text: String) -> String {
        var result = ""
        var rest = text[...]
        while let open = rest.range(of: "<!--") {
            result += rest[..<open.lowerBound]
            guard let close = rest[open.upperBound...].range(of: "-->") else {
                // An unterminated comment hides the rest of the file, as in Markdown.
                return result
            }
            rest = rest[close.upperBound...]
        }
        return result + rest
    }

    static func droppingFrontMatter(_ lines: [String]) -> [String] {
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return lines }
        let closing = lines.dropFirst().firstIndex { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed == "---" || trimmed == "..."
        }
        guard let closing else { return lines }
        return Array(lines[(closing + 1)...])
    }
}

/// Block-level structure: which lines form a paragraph, which are headings.
enum BlockScanner {

    enum RawBlock: Equatable {
        case paragraph([String])
        case heading(String)
    }

    static func scan(_ lines: [String]) -> [RawBlock] {
        var state = State()
        for line in lines {
            state.consume(line.trimmingCharacters(in: .whitespaces))
        }
        state.flush()
        return state.blocks
    }

    private struct State {
        var blocks: [RawBlock] = []
        var current: [String] = []
        var openFence: String?

        mutating func flush() {
            if !current.isEmpty {
                blocks.append(.paragraph(current))
            }
            current = []
        }

        mutating func consume(_ trimmed: String) {
            if let fence = openFence {
                if trimmed.hasPrefix(fence) {
                    openFence = nil
                    flush()
                } else if !trimmed.isEmpty {
                    current.append(trimmed)
                }
                return
            }
            if let fence = BlockScanner.fenceMarker(trimmed) {
                flush()
                openFence = fence
                return
            }
            consumeOutsideFence(BlockScanner.strippingBlockquote(trimmed))
        }

        private mutating func consumeOutsideFence(_ content: String) {
            if content.isEmpty {
                flush()
            } else if !current.isEmpty, BlockScanner.isSetextUnderline(content) {
                let heading = current.joined(separator: " ")
                current = []
                blocks.append(.heading(heading))
            } else if BlockScanner.isThematicBreak(content) {
                flush()
            } else if let heading = BlockScanner.atxHeading(content) {
                flush()
                blocks.append(.heading(heading))
            } else if let item = BlockScanner.listItemContent(content) {
                flush()
                current = [item]
            } else {
                current.append(content)
            }
        }
    }

    static func fenceMarker(_ line: String) -> String? {
        if line.hasPrefix("```") { return "```" }
        if line.hasPrefix("~~~") { return "~~~" }
        return nil
    }

    static func strippingBlockquote(_ line: String) -> String {
        var content = Substring(line)
        while content.first == ">" {
            content = content.dropFirst().drop { $0 == " " }
        }
        return String(content)
    }

    static func isSetextUnderline(_ line: String) -> Bool {
        guard let first = line.first, first == "=" || first == "-" else { return false }
        return line.allSatisfy { $0 == first }
    }

    static func isThematicBreak(_ line: String) -> Bool {
        let marks = line.filter { $0 != " " }
        guard marks.count >= 3, let first = marks.first, "-*_".contains(first) else { return false }
        return marks.allSatisfy { $0 == first }
    }

    static func atxHeading(_ line: String) -> String? {
        let hashes = line.prefix { $0 == "#" }
        guard (1...6).contains(hashes.count) else { return nil }
        let rest = line.dropFirst(hashes.count)
        guard rest.isEmpty || rest.first == " " else { return nil }
        var text = rest.trimmingCharacters(in: .whitespaces)
        while text.hasSuffix("#") {
            text.removeLast()
        }
        return text.trimmingCharacters(in: .whitespaces)
    }

    static func listItemContent(_ line: String) -> String? {
        var rest: Substring
        if let first = line.first, "-*+".contains(first), line.dropFirst().first == " " {
            rest = line.dropFirst(2)
        } else {
            let digits = line.prefix(while: \.isNumber)
            let afterDigits = line.dropFirst(digits.count)
            guard (1...9).contains(digits.count),
                  let marker = afterDigits.first, marker == "." || marker == ")",
                  afterDigits.dropFirst().first == " " else { return nil }
            rest = afterDigits.dropFirst(2)
        }
        rest = rest.drop { $0 == " " }
        for box in ["[ ] ", "[x] ", "[X] "] where rest.hasPrefix(box) {
            rest = rest.dropFirst(box.count)
        }
        return String(rest)
    }
}
