import Foundation
import Testing
@testable import NotchPrompterKit

@Suite("Recording naming")
struct RecordingNamingTests {

    @Test("slugs keep letters and digits and join the rest with single hyphens", arguments: [
        ("Product Launch", "product-launch"),
        ("  Q3 / Q4: the plan!  ", "q3-q4-the-plan"),
        ("Café déjà vu", "café-déjà-vu"),
        ("***", RecordingNaming.fallbackSlug),
        ("", RecordingNaming.fallbackSlug)
    ])
    func slugs(title: String, expected: String) {
        #expect(RecordingNaming.slug(for: title) == expected)
    }

    @Test("no script means a plain take")
    func noScript() {
        #expect(RecordingNaming.slug(for: nil) == "take")
    }

    @Test("long titles are cut without a trailing hyphen")
    func longTitle() {
        let slug = RecordingNaming.slug(for: String(repeating: "a", count: 59) + " bcd")
        #expect(slug == String(repeating: "a", count: 59))
    }

    @Test("names lead with a local timestamp")
    func fileName() throws {
        let toronto = try #require(TimeZone(identifier: "America/Toronto"))
        // 2026-10-12 18:32:05 UTC is 14:32:05 in Toronto (EDT).
        let date = Date(timeIntervalSince1970: 1_791_829_925)
        #expect(
            RecordingNaming.fileName(scriptTitle: "Product Launch", date: date, timeZone: toronto)
                == "2026-10-12-143205-product-launch.mov"
        )
    }

    @Test("a taken name gets a counter before the extension, ignoring case")
    func unique() {
        let existing: Set = ["a.mov", "A-2.MOV"]
        #expect(RecordingNaming.uniqueFileName("a.mov", existing: existing) == "a-3.mov")
        #expect(RecordingNaming.uniqueFileName("b.mov", existing: existing) == "b.mov")
    }
}
