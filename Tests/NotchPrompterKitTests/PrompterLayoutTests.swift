import Foundation
import Testing
@testable import NotchPrompterKit

/// Ten points per character keeps wrapping arithmetic obvious in tests.
func monospaced(_ text: String) -> Double {
    Double(text.count) * 10
}

func layout(_ blocks: [PrompterBlock], width: Double = 100) -> PrompterLayout {
    PrompterLayout(document: PrompterDocument(blocks: blocks), width: width, measure: monospaced)
}

@Suite("Prompter layout")
struct PrompterLayoutTests {

    @Test("wraps words greedily to the column width")
    func wraps() {
        // 10 characters fit in 100 points.
        let lines = layout([.speech("one two three four five")]).lines.map(\.text)
        #expect(lines == ["one two", "three four", "five"])
    }

    @Test("gives an over-long word a line of its own instead of splitting it")
    func longWord() {
        let lines = layout([.speech("a supercalifragilistic b")]).lines.map(\.text)
        #expect(lines == ["a", "supercalifragilistic", "b"])
    }

    @Test("marks block starts and keeps kinds and block indices")
    func lineMetadata() {
        let lines = layout([.note("look up"), .speech("one two three"), .pause(3)]).lines
        #expect(lines.map(\.kind) == [.note, .speech, .speech, .pause(3)])
        #expect(lines.map(\.blockIndex) == [0, 1, 1, 2])
        #expect(lines.map(\.startsBlock) == [true, true, false, true])
        #expect(lines.map(\.wordCount) == [2, 2, 1, 0])
    }

    @Test("clamps positions into the script")
    func clamping() {
        let subject = layout([.speech("one two three")])
        #expect(subject.clamped(-1) == 0)
        #expect(subject.clamped(9) == 2)
        #expect(subject.clamped(.nan) == 0)
        #expect(subject.lineIndex(at: 1.7) == 1)
        #expect(subject.lineIndex(at: 2) == nil)
    }
}

@Suite("Paragraph jumps")
struct ParagraphJumpTests {

    // Blocks start at lines 0, 2, and 4.
    let subject = layout([.speech("one two three"), .speech("four five six"), .speech("seven")])

    @Test("back from well inside a paragraph returns to its start")
    func backRestarts() {
        #expect(subject.previousBlockStart(from: 3.2) == 2)
    }

    @Test("back from the start of a paragraph goes to the previous one")
    func backToPrevious() {
        #expect(subject.previousBlockStart(from: 2.3) == 0)
        #expect(subject.previousBlockStart(from: 4) == 2)
    }

    @Test("back from the first paragraph stays at the top")
    func backAtTop() {
        #expect(subject.previousBlockStart(from: 0.2) == 0)
    }

    @Test("forward goes to the next paragraph, or the end")
    func forward() {
        #expect(subject.nextBlockStart(from: 0) == 2)
        #expect(subject.nextBlockStart(from: 2.9) == 4)
        #expect(subject.nextBlockStart(from: 4.1) == 5)
    }
}

@Suite("Relayout")
struct RelayoutTests {

    @Test("keeps the reader in the same paragraph, the same fraction through")
    func carriesPosition() {
        let blocks: [PrompterBlock] = [.speech("aaaa bbbb cccc dddd"), .speech("eeee ffff gggg hhhh")]
        let narrow = layout(blocks, width: 40) // four lines per block
        let wide = layout(blocks, width: 90) // two lines per block
        #expect(narrow.lines.count == 8)
        #expect(wide.lines.count == 4)
        #expect(narrow.position(6, in: wide) == 3) // halfway through block 1
        #expect(narrow.position(1, in: wide) == 0.5)
    }

    @Test("the end stays the end")
    func carriesEnd() {
        let blocks: [PrompterBlock] = [.speech("aaaa bbbb cccc dddd")]
        #expect(layout(blocks, width: 40).position(4, in: layout(blocks, width: 90)) == 2)
    }
}
