import Foundation

/// Finds `[pause]` and `[note: …]` cues in a paragraph and splits it around them.
enum Cues {

    enum Cue: Equatable {
        case pause(TimeInterval)
        case note(String)
    }

    /// Splits raw paragraph text into speech, note, and pause blocks, in order.
    ///
    /// Markup is removed from the speech pieces after the split, so a cue
    /// never reaches the inline cleaner and cannot be mistaken for a link.
    static func split(_ paragraph: String) -> [PrompterBlock] {
        var blocks: [PrompterBlock] = []
        var pending = ""

        func flushSpeech() {
            let text = InlineMarkdown.plainText(pending)
            if !text.isEmpty {
                blocks.append(.speech(text))
            }
            pending = ""
        }

        var index = paragraph.startIndex
        while index < paragraph.endIndex {
            if paragraph[index] == "[", let (cue, end) = cue(in: paragraph, at: index) {
                flushSpeech()
                switch cue {
                case .pause(let seconds):
                    blocks.append(.pause(seconds))
                case .note(let text) where !text.isEmpty:
                    blocks.append(.note(text))
                case .note:
                    break
                }
                index = end
            } else {
                pending.append(paragraph[index])
                index = paragraph.index(after: index)
            }
        }
        flushSpeech()
        return blocks
    }

    /// Parses a cue that opens at `start`, returning it and the index after its `]`.
    static func cue(in text: String, at start: String.Index) -> (Cue, String.Index)? {
        let afterBracket = text.index(after: start)
        guard let close = text[afterBracket...].firstIndex(of: "]") else { return nil }
        let end = text.index(after: close)
        if end < text.endIndex, text[end] == "(" {
            return nil
        }
        let body = text[afterBracket..<close]
        guard let parsed = parse(body) else { return nil }
        return (parsed, end)
    }

    static func parse(_ body: Substring) -> Cue? {
        let lowered = body.lowercased()
        if let argument = argument(of: "pause", in: lowered) {
            return .pause(pauseSeconds(argument))
        }
        if argument(of: "note", in: lowered) != nil {
            let original = body.dropFirst("note".count)
            let text = InlineMarkdown.plainText(
                String(original.drop { $0 == ":" || $0 == " " })
            )
            return .note(text)
        }
        return nil
    }

    /// The text after a cue keyword, or `nil` if the body is not that cue.
    private static func argument(of keyword: String, in body: String) -> String? {
        guard body.hasPrefix(keyword) else { return nil }
        let rest = body.dropFirst(keyword.count)
        guard rest.isEmpty || rest.first == " " || rest.first == ":" else { return nil }
        return rest.drop { $0 == ":" || $0 == " " }.trimmingCharacters(in: .whitespaces)
    }

    private static func pauseSeconds(_ argument: String) -> TimeInterval {
        var number = Substring(argument)
        for unit in ["seconds", "second", "secs", "sec", "s"] where number.hasSuffix(unit) {
            number = number.dropLast(unit.count)
            break
        }
        guard let seconds = TimeInterval(number.trimmingCharacters(in: .whitespaces)),
              seconds > 0, seconds.isFinite else {
            return ScriptParser.defaultPause
        }
        return seconds
    }
}
