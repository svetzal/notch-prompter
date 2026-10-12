import Foundation
import Testing
@testable import NotchPrompterKit

@Suite("Script parsing")
struct ScriptParserTests {

    private func blocks(_ markdown: String) -> [PrompterBlock] {
        ScriptParser.blocks(from: markdown)
    }

    @Test("joins soft line breaks and keeps paragraph breaks")
    func paragraphs() {
        let result = blocks("""
        First line
        continues here.

        Second paragraph.
        """)
        #expect(result == [.speech("First line continues here."), .speech("Second paragraph.")])
    }

    @Test("collapses runs of blank lines and whitespace")
    func whitespace() {
        let result = blocks("\n\n  One   two\t three  \n\n\n\nFour\n\n")
        #expect(result == [.speech("One two three"), .speech("Four")])
    }

    @Test("treats Windows and classic Mac line endings like Unix ones")
    func lineEndings() {
        #expect(blocks("One\r\n\r\nTwo\rThree") == [.speech("One"), .speech("Two Three")])
    }

    @Test("turns ATX and setext headings into notes")
    func headings() {
        let result = blocks("""
        # Opening ##

        Hello.

        Section two
        -----------

        Bye.

        Big title
        =========
        """)
        #expect(result == [
            .note("Opening"), .speech("Hello."), .note("Section two"), .speech("Bye."), .note("Big title")
        ])
    }

    @Test("does not mistake a hashtag for a heading")
    func hashtag() {
        #expect(blocks("#swift is fun") == [.speech("#swift is fun")])
    }

    @Test("makes each list item its own paragraph without its marker")
    func listItems() {
        let result = blocks("""
        - first
          wraps on
        * second
        + third
        1. fourth
        2) fifth
        - [x] done task
        """)
        #expect(result == [
            .speech("first wraps on"), .speech("second"), .speech("third"),
            .speech("fourth"), .speech("fifth"), .speech("done task")
        ])
    }

    @Test("removes emphasis, code, and strikethrough markup")
    func emphasis() {
        let result = blocks("This is **bold**, *italic*, __strong__, _em_, `code`, and ~~gone~~ text.")
        #expect(result == [.speech("This is bold, italic, strong, em, code, and gone text.")])
    }

    @Test("keeps underscores inside words")
    func intrawordUnderscore() {
        #expect(blocks("Call snake_case_names out.") == [.speech("Call snake_case_names out.")])
    }

    @Test("keeps link text and drops images")
    func linksAndImages() {
        let result = blocks("Read [the docs](https://example.com) and [the ref][1]. ![logo](logo.png)Done.")
        #expect(result == [.speech("Read the docs and the ref. Done.")])
    }

    @Test("honours backslash escapes")
    func escapes() {
        #expect(blocks(#"Five \* three is \_fifteen\_."#) == [.speech("Five * three is _fifteen_.")])
    }

    @Test("drops HTML tags but keeps autolinks and comparison signs")
    func angleBrackets() {
        let result = blocks("Line<br>break <span class=\"x\">kept</span> <https://x.io> and 1 < 2 > 0, x<y and y>z.")
        #expect(result == [.speech("Linebreak kept https://x.io and 1 < 2 > 0, x<y and y>z.")])
    }

    @Test("decodes common HTML entities")
    func entities() {
        #expect(blocks("Fish &amp; chips &lt;3") == [.speech("Fish & chips <3")])
    }

    @Test("removes HTML comments, including multi-line ones")
    func comments() {
        let result = blocks("""
        Keep this. <!-- inline aside -->

        <!--
        A whole hidden paragraph.
        -->

        And this.
        """)
        #expect(result == [.speech("Keep this."), .speech("And this.")])
    }

    @Test("treats an unterminated comment as hiding the rest of the file")
    func unterminatedComment() {
        #expect(blocks("Shown.\n\n<!-- never closed\n\nHidden.") == [.speech("Shown.")])
    }

    @Test("ignores YAML front matter")
    func frontMatter() {
        let result = blocks("""
        ---
        title: Intro
        ---
        Hello.
        """)
        #expect(result == [.speech("Hello.")])
    }

    @Test("strips blockquote markers and code fences")
    func quotesAndFences() {
        let result = blocks("""
        > Quoted
        > > nested

        ```swift
        let x = 1
        ```
        """)
        #expect(result == [.speech("Quoted nested"), .speech("let x = 1")])
    }

    @Test("treats thematic breaks as paragraph boundaries")
    func thematicBreak() {
        #expect(blocks("One\n\n***\n\nTwo\n\n- - -\n\nThree") == [.speech("One"), .speech("Two"), .speech("Three")])
    }
}

@Suite("Script cues")
struct CueTests {

    private func blocks(_ markdown: String) -> [PrompterBlock] {
        ScriptParser.blocks(from: markdown)
    }

    @Test("a bare pause holds for the default time")
    func barePause() {
        #expect(blocks("One.\n\n[pause]\n\nTwo.") == [.speech("One."), .pause(ScriptParser.defaultPause), .speech("Two.")])
    }

    @Test("a pause takes seconds with or without a unit", arguments: [
        ("[pause 3]", 3.0), ("[pause 1.5s]", 1.5), ("[Pause: 4 sec]", 4.0), ("[PAUSE 2 seconds]", 2.0)
    ])
    func pauseDurations(cue: String, seconds: Double) {
        #expect(blocks(cue) == [.pause(seconds)])
    }

    @Test("a pause with a nonsense length falls back to the default", arguments: ["[pause soon]", "[pause -1]", "[pause 0]"])
    func invalidPause(cue: String) {
        #expect(blocks(cue) == [.pause(ScriptParser.defaultPause)])
    }

    @Test("a cue inside a paragraph splits it")
    func inlineCue() {
        let result = blocks("Hello there. [pause] And **now** [note: look left] the news.")
        #expect(result == [
            .speech("Hello there."), .pause(ScriptParser.defaultPause), .speech("And now"),
            .note("look left"), .speech("the news.")
        ])
    }

    @Test("a note keeps its own wording, minus markup")
    func noteText() {
        #expect(blocks("[note: *Breathe*, then smile]") == [.note("Breathe, then smile")])
        #expect(blocks("[note slow down]") == [.note("slow down")])
    }

    @Test("an empty note is dropped")
    func emptyNote() {
        #expect(blocks("[note:]") == [])
    }

    @Test("brackets that are not cues are left as text")
    func notACue() {
        #expect(blocks("An [aside] and [pauseless] words.") == [.speech("An [aside] and [pauseless] words.")])
    }

    @Test("a link whose text looks like a cue stays a link")
    func linkLookingLikeCue() {
        #expect(blocks("See [pause](https://example.com) docs.") == [.speech("See pause docs.")])
    }
}

@Suite("Prompter document")
struct PrompterDocumentTests {

    @Test("counts only spoken words")
    func spokenWords() {
        let document = PrompterDocument(markdown: "# Title words\n\nOne two three.\n\n[note: not counted]\n\nFour five.")
        #expect(document.spokenWordCount == 5)
    }

    @Test("estimates reading time from speed plus pauses")
    func readingTime() {
        let document = PrompterDocument(blocks: [.speech("one two three four"), .pause(2.5), .speech("five six")])
        #expect(document.estimatedReadingTime(wordsPerMinute: 120) == 5.5)
        #expect(document.totalPauseTime == 2.5)
    }

    @Test("the sample script demonstrates notes, pauses, and hidden comments")
    func sampleScript() {
        let blocks = PrompterDocument(markdown: SampleScript.markdown).blocks
        #expect(blocks.first == .note("Welcome"))
        #expect(blocks.contains(.pause(2)))
        #expect(blocks.contains { if case .note(let text) = $0 { text.hasPrefix("Smile") } else { false } })
        #expect(!blocks.contains { if case .speech(let text) = $0 { text.contains("Comments") } else { false } })
    }
}
