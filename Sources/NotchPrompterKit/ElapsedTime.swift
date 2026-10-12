import Foundation

/// Clock-style durations for the take timer and reading estimates.
public enum ElapsedTime {

    /// `0:05`, `12:34`, `1:02:03`. Fractions of a second are dropped, not
    /// rounded, so a timer never shows a second that has not passed yet.
    /// Negative and non-finite values read as zero.
    public static func format(_ interval: TimeInterval) -> String {
        let total = interval.isFinite ? max(0, Int(interval.rounded(.down))) : 0
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}
