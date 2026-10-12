import Foundation

/// One of a plug-in's parameters, for the parameter list the app shows when
/// a plug-in has no window of its own, or as an alternative to it.
///
/// It copies what the plug-in's parameter tree says, and decides which
/// control fits: a switch, a choice, a slider, or a read-only value.
public struct PluginParameter: Equatable, Identifiable, Sendable {

    /// The Audio Unit parameter unit codes this list treats specially
    /// (`AudioUnitParameterUnit`).
    public enum Unit {
        public static let generic: UInt32 = 0
        public static let indexed: UInt32 = 1
        public static let boolean: UInt32 = 2
        public static let percent: UInt32 = 3
        public static let seconds: UInt32 = 4
        public static let hertz: UInt32 = 8
        public static let decibels: UInt32 = 13
        public static let milliseconds: UInt32 = 24
        public static let customUnit: UInt32 = 26
    }

    public enum Control: Equatable, Sendable {
        case toggle
        /// One name for each whole step from the minimum to the maximum.
        case choice([String])
        case slider(ClosedRange<Float>)
        case readOnly
    }

    public let address: UInt64
    public let name: String
    public let minValue: Float
    public let maxValue: Float
    public var value: Float
    public let unit: UInt32
    /// The plug-in's own unit name, used for its custom unit.
    public let unitName: String?
    public let valueStrings: [String]?
    public let isWritable: Bool

    public var id: UInt64 { address }

    public init(
        address: UInt64, name: String, minValue: Float, maxValue: Float, value: Float,
        unit: UInt32, unitName: String?, valueStrings: [String]?, isWritable: Bool
    ) {
        self.address = address
        self.name = name
        self.minValue = minValue
        self.maxValue = maxValue
        self.value = value
        self.unit = unit
        self.unitName = unitName
        self.valueStrings = valueStrings
        self.isWritable = isWritable
    }

    public var control: Control {
        guard isWritable else { return .readOnly }
        if unit == Unit.boolean {
            return .toggle
        }
        if let valueStrings, !valueStrings.isEmpty, Float(valueStrings.count - 1) == maxValue - minValue {
            return .choice(valueStrings)
        }
        return minValue < maxValue ? .slider(minValue...maxValue) : .readOnly
    }

    /// `value`, kept inside the parameter's range.
    public var clampedValue: Float {
        min(max(value, minValue), maxValue)
    }

    public var displayValue: String {
        if unit == Unit.boolean {
            return value >= 0.5 ? "On" : "Off"
        }
        if case .choice(let names) = control {
            let index = Int((clampedValue - minValue).rounded())
            return names.indices.contains(index) ? names[index] : String(format: "%.0f", value)
        }
        let magnitude = abs(value)
        let number = String(format: magnitude >= 100 ? "%.0f" : magnitude >= 10 ? "%.1f" : "%.2f", value)
        return symbol.map { "\(number) \($0)" } ?? number
    }

    private var symbol: String? {
        switch unit {
        case Unit.percent: "%"
        case Unit.seconds: "s"
        case Unit.hertz: "Hz"
        case Unit.decibels: "dB"
        case Unit.milliseconds: "ms"
        case Unit.customUnit: unitName
        default: nil
        }
    }
}
