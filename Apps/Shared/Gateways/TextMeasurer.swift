import AppKit

/// Measures prompter text in the font ``PrompterView`` draws it with.
enum TextMeasurer {

    static let weight = NSFont.Weight.semibold

    @MainActor
    static func width(of text: String, fontSize: Double) -> Double {
        let font = NSFont.systemFont(ofSize: fontSize, weight: weight)
        return (text as NSString).size(withAttributes: [.font: font]).width
    }
}
