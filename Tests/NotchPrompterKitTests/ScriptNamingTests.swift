import Testing
@testable import NotchPrompterKit

@Suite("Script naming")
struct ScriptNamingTests {

    @Test("recognizes Markdown files and skips hidden ones", arguments: [
        ("Intro.md", true), ("Intro.MD", true), ("notes.markdown", true),
        ("Intro.txt", false), (".Intro.md", false), ("Intro", false)
    ])
    func recognizesScripts(fileName: String, expected: Bool) {
        #expect(ScriptNaming.isScript(fileName: fileName) == expected)
    }

    @Test("a title is the file name without its extension")
    func title() {
        #expect(ScriptNaming.title(forFileName: "Product launch.md") == "Product launch")
    }

    @Test("sanitizes titles into safe file names")
    func sanitize() {
        #expect(ScriptNaming.sanitizedTitle("Q3/Q4: plan") == "Q3-Q4- plan")
        #expect(ScriptNaming.sanitizedTitle("  ..hidden  ") == "hidden")
        #expect(ScriptNaming.sanitizedTitle("tab\there") == "tabhere")
        #expect(ScriptNaming.sanitizedTitle("   ") == ScriptNaming.untitled)
    }

    @Test("avoids collisions, ignoring case")
    func unique() {
        let existing: Set = ["Intro.md", "intro 2.md", "Other.md"]
        #expect(ScriptNaming.uniqueFileName(forTitle: "Intro", existing: existing) == "Intro 3.md")
        #expect(ScriptNaming.uniqueFileName(forTitle: "Fresh", existing: existing) == "Fresh.md")
        #expect(ScriptNaming.uniqueFileName(forTitle: "", existing: []) == "Untitled.md")
    }

    @Test("sorts by title in numeric order")
    func sorting() {
        let sorted = ScriptNaming.sortedForDisplay(["Take 10.md", "apple.md", "Take 2.md", "Banana.md"])
        #expect(sorted == ["apple.md", "Banana.md", "Take 2.md", "Take 10.md"])
    }
}
