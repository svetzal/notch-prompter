import Foundation

/// An installed Audio Unit, named by the three codes that find it again.
///
/// The codes are what `auval -a` prints: type, subtype, manufacturer. They
/// identify a plug-in across app launches and plug-in updates, so the voice
/// chain stores them, not a path or an index.
public struct AudioUnitComponent: Codable, Hashable, Sendable {
    /// The type of an effect that processes audio: `aufx`.
    public static let effectType = code("aufx")

    public let type: UInt32
    public let subtype: UInt32
    public let manufacturer: UInt32
    public let name: String
    public let manufacturerName: String

    public init(type: UInt32, subtype: UInt32, manufacturer: UInt32, name: String, manufacturerName: String) {
        self.type = type
        self.subtype = subtype
        self.manufacturer = manufacturer
        self.name = name
        self.manufacturerName = manufacturerName
    }

    /// Type, subtype, and manufacturer as text, for example `aufx lmtr appl`.
    public var codes: String {
        [type, subtype, manufacturer].map(Self.text(for:)).joined(separator: " ")
    }

    /// The effects the chain offers, from everything installed: effects
    /// (`aufx`) only, each once, sorted by maker and then name.
    ///
    /// Music effects (`aumf`) also take MIDI and are built for instruments,
    /// so they are left out.
    public static func offeredEffects(from installed: [AudioUnitComponent]) -> [AudioUnitComponent] {
        var seen = Set<AudioUnitComponent>()
        return installed
            .filter { $0.type == effectType && seen.insert($0).inserted }
            .sorted {
                let makers = $0.manufacturerName.localizedStandardCompare($1.manufacturerName)
                return makers == .orderedSame
                    ? $0.name.localizedStandardCompare($1.name) == .orderedAscending
                    : makers == .orderedAscending
            }
    }

    /// The four-character code for `text`, which must be four ASCII characters.
    public static func code(_ text: String) -> UInt32 {
        text.utf8.prefix(4).reduce(0) { ($0 << 8) | UInt32($1) }
    }

    /// A four-character code as text, or as hex when it has a character that is not printable.
    public static func text(for code: UInt32) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }
        guard bytes.allSatisfy({ (0x20...0x7E).contains($0) }), let text = String(bytes: bytes, encoding: .ascii) else {
            return String(format: "0x%08x", code)
        }
        return text
    }
}
