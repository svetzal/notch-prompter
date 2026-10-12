/// The prompter's keyboard controls, independent of AppKit's event types.
public enum PrompterKeyCommand: Equatable, Sendable, CaseIterable {
    case togglePlayback
    case stop
    case faster
    case slower
    case nudgeBack
    case nudgeForward
    case previousParagraph
    case nextParagraph
    case rewindToStart
    case largerText
    case smallerText

    /// Modifier keys held with a key press.
    public struct Modifiers: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let command = Modifiers(rawValue: 1 << 0)
        public static let shift = Modifiers(rawValue: 1 << 1)
        public static let option = Modifiers(rawValue: 1 << 2)
        public static let control = Modifiers(rawValue: 1 << 3)
    }

    // AppKit's private-use characters for special keys (NSUpArrowFunctionKey and friends).
    static let upArrow: Character = "\u{F700}"
    static let downArrow: Character = "\u{F701}"
    static let leftArrow: Character = "\u{F702}"
    static let rightArrow: Character = "\u{F703}"
    static let home: Character = "\u{F729}"
    static let escape: Character = "\u{1B}"

    /// Maps a key press, as AppKit's `charactersIgnoringModifiers` reports it,
    /// to a prompter command. Returns `nil` for keys the prompter leaves alone.
    ///
    /// Shift is ignored so that `+` (shift-`=`) works on any layout. Control
    /// and Option combinations are never claimed.
    public init?(characters: String, modifiers: Modifiers) {
        guard characters.count == 1, let key = characters.first,
              modifiers.isDisjoint(with: [.control, .option]) else { return nil }
        let command = if modifiers.contains(.command) {
            Self.commandKeyMap[key]
        } else {
            Self.plainKeyMap[key]
        }
        guard let command else { return nil }
        self = command
    }

    private static let plainKeyMap: [Character: PrompterKeyCommand] = [
        " ": .togglePlayback,
        escape: .stop,
        "=": .faster,
        "+": .faster,
        "-": .slower,
        "_": .slower,
        upArrow: .nudgeBack,
        downArrow: .nudgeForward,
        leftArrow: .previousParagraph,
        rightArrow: .nextParagraph,
        home: .rewindToStart
    ]

    private static let commandKeyMap: [Character: PrompterKeyCommand] = [
        "=": .largerText,
        "+": .largerText,
        "-": .smallerText,
        upArrow: .rewindToStart
    ]

    /// The key a person presses, for help text and menus.
    public var keyLabel: String {
        switch self {
        case .togglePlayback: "Space"
        case .stop: "Esc"
        case .faster: "+"
        case .slower: "−"
        case .nudgeBack: "↑"
        case .nudgeForward: "↓"
        case .previousParagraph: "←"
        case .nextParagraph: "→"
        case .rewindToStart: "⌘↑"
        case .largerText: "⌘+"
        case .smallerText: "⌘−"
        }
    }

    public var summary: String {
        switch self {
        case .togglePlayback: "Start, pause, or resume"
        case .stop: "Stop the take, or hide the prompter"
        case .faster: "Faster"
        case .slower: "Slower"
        case .nudgeBack: "Back one line"
        case .nudgeForward: "Forward one line"
        case .previousParagraph: "Back a paragraph"
        case .nextParagraph: "Forward a paragraph"
        case .rewindToStart: "Back to the start"
        case .largerText: "Larger text"
        case .smallerText: "Smaller text"
        }
    }
}
