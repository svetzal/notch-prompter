import Foundation

/// File names for recorded takes.
///
/// Names lead with a sortable timestamp so Finder lists takes in the order
/// they were made, then carry the script's title so a take is recognisable
/// without opening it: `2026-10-12-143205-product-launch.mov`. A vertical
/// take ends in `-vertical`, so the two shapes are easy to tell apart.
public enum RecordingNaming {

    public static let fileExtension = "mov"
    /// The name part used when there is no script, or its title has no usable characters.
    public static let fallbackSlug = "take"
    static let maximumSlugLength = 60

    /// Lower-case letters and digits from the title, joined by single hyphens.
    public static func slug(for title: String?) -> String {
        guard let title else { return fallbackSlug }
        var slug = ""
        var pendingHyphen = false
        for character in title.lowercased() {
            if character.isLetter || character.isNumber {
                if pendingHyphen, !slug.isEmpty {
                    slug.append("-")
                }
                slug.append(character)
                pendingHyphen = false
            } else {
                pendingHyphen = true
            }
        }
        if slug.count > maximumSlugLength {
            slug = String(slug.prefix(maximumSlugLength))
            while slug.hasSuffix("-") {
                slug.removeLast()
            }
        }
        return slug.isEmpty ? fallbackSlug : slug
    }

    /// The name for a take of `scriptTitle` in `format`, started at `date`, in local time.
    public static func fileName(
        scriptTitle: String?,
        date: Date,
        format: VideoFormat = .horizontal,
        timeZone: TimeZone = .current
    ) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let stamp = String(
            format: "%04d-%02d-%02d-%02d%02d%02d",
            parts.year ?? 0, parts.month ?? 0, parts.day ?? 0,
            parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0
        )
        let suffix = format.fileNameSuffix.map { "-\($0)" } ?? ""
        return "\(stamp)-\(slug(for: scriptTitle))\(suffix).\(fileExtension)"
    }

    /// `name`, or `name` with `-2`, `-3`… before the extension if it is taken.
    public static func uniqueFileName(_ name: String, existing: Set<String>) -> String {
        let taken = Set(existing.map { $0.lowercased() })
        guard taken.contains(name.lowercased()) else { return name }
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var counter = 2
        while true {
            let candidate = ext.isEmpty ? "\(base)-\(counter)" : "\(base)-\(counter).\(ext)"
            if !taken.contains(candidate.lowercased()) {
                return candidate
            }
            counter += 1
        }
    }
}
