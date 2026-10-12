import Foundation
import Testing
@testable import NotchPrompterKit

@Suite("Elapsed time")
struct ElapsedTimeTests {

    @Test("formats like a clock", arguments: [
        (0.0, "0:00"), (5.9, "0:05"), (65, "1:05"), (754, "12:34"), (3723, "1:02:03")
    ])
    func formats(interval: TimeInterval, expected: String) {
        #expect(ElapsedTime.format(interval) == expected)
    }

    @Test("reads nonsense as zero", arguments: [-3.0, .infinity, .nan])
    func nonsense(interval: TimeInterval) {
        #expect(ElapsedTime.format(interval) == "0:00")
    }
}
