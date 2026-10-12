import Foundation

/// One unit of prompter content, derived from a Markdown script.
public enum PrompterBlock: Equatable, Sendable {
    /// Text the presenter reads aloud.
    case speech(String)
    /// Text shown to the presenter but not read aloud: headings and `[note: …]` cues.
    case note(String)
    /// A timed hold, from a `[pause]` cue.
    case pause(TimeInterval)
}

/// A script turned into prompter content.
///
/// The prompter never sees Markdown. It sees an ordered list of blocks, where
/// each block is one paragraph, note, or pause. Paragraph boundaries survive
/// so that "jump back a paragraph" means what the author wrote.
public struct PrompterDocument: Equatable, Sendable {

    public let blocks: [PrompterBlock]

    public init(blocks: [PrompterBlock]) {
        self.blocks = blocks
    }

    /// Parses a Markdown script. See ``ScriptParser`` for the rules.
    public init(markdown: String) {
        self.init(blocks: ScriptParser.blocks(from: markdown))
    }

    /// The number of words the presenter reads aloud. Notes do not count.
    public var spokenWordCount: Int {
        blocks.reduce(0) { total, block in
            if case .speech(let text) = block {
                return total + Words.count(in: text)
            }
            return total
        }
    }

    /// The total length of all pause cues.
    public var totalPauseTime: TimeInterval {
        blocks.reduce(0) { total, block in
            if case .pause(let seconds) = block {
                return total + seconds
            }
            return total
        }
    }

    /// How long a read-through takes at a given speed, counting pauses.
    public func estimatedReadingTime(wordsPerMinute: Double) -> TimeInterval {
        guard wordsPerMinute > 0 else { return totalPauseTime }
        return Double(spokenWordCount) * 60 / wordsPerMinute + totalPauseTime
    }
}

/// Word splitting shared by the parser, layout, and timing.
enum Words {
    static func split(_ text: String) -> [Substring] {
        text.split(whereSeparator: \.isWhitespace)
    }

    static func count(in text: String) -> Int {
        split(text).count
    }
}
