import Testing
@testable import NotchPrompterKit

private func parameter(
    unit: UInt32 = PluginParameter.Unit.generic,
    range: ClosedRange<Float> = 0...1,
    value: Float = 0.5,
    unitName: String? = nil,
    valueStrings: [String]? = nil,
    isWritable: Bool = true
) -> PluginParameter {
    PluginParameter(
        address: 7, name: "Amount", minValue: range.lowerBound, maxValue: range.upperBound, value: value,
        unit: unit, unitName: unitName, valueStrings: valueStrings, isWritable: isWritable
    )
}

@Suite("Plug-in parameters")
struct PluginParameterTests {

    @Test("a boolean parameter is a switch")
    func toggle() {
        let flag = parameter(unit: PluginParameter.Unit.boolean, value: 1)
        #expect(flag.control == .toggle)
        #expect(flag.displayValue == "On")
        #expect(parameter(unit: PluginParameter.Unit.boolean, value: 0).displayValue == "Off")
    }

    @Test("a parameter with a name for each step is a choice")
    func choice() {
        let mode = parameter(unit: PluginParameter.Unit.indexed, range: 0...2, value: 1, valueStrings: ["Low", "Mid", "High"])
        #expect(mode.control == .choice(["Low", "Mid", "High"]))
        #expect(mode.displayValue == "Mid")
    }

    @Test("names that do not match the steps fall back to a slider")
    func mismatchedNames() {
        let mode = parameter(unit: PluginParameter.Unit.indexed, range: 0...4, value: 1, valueStrings: ["A", "B"])
        #expect(mode.control == .slider(0...4))
    }

    @Test("a continuous parameter is a slider over its range")
    func slider() {
        #expect(parameter(range: -20...6).control == .slider(-20...6))
    }

    @Test("a parameter the plug-in does not let the host change, or with no range, is shown only")
    func readOnly() {
        #expect(parameter(isWritable: false).control == .readOnly)
        #expect(parameter(range: 1...1, value: 1).control == .readOnly)
    }

    @Test("values show with their unit and sensible precision", arguments: [
        (PluginParameter.Unit.decibels, Float(-3.25), nil as String?, "-3.25 dB"),
        (PluginParameter.Unit.hertz, Float(1_250), nil, "1250 Hz"),
        (PluginParameter.Unit.milliseconds, Float(12.5), nil, "12.5 ms"),
        (PluginParameter.Unit.percent, Float(50), nil, "50.0 %"),
        (PluginParameter.Unit.customUnit, Float(2), "x", "2.00 x"),
        (PluginParameter.Unit.generic, Float(0.5), nil, "0.50")
    ])
    func display(unit: UInt32, value: Float, unitName: String?, expected: String) {
        #expect(parameter(unit: unit, range: -10_000...10_000, value: value, unitName: unitName).displayValue == expected)
    }

    @Test("a new value is kept inside the range")
    func clamped() {
        var amount = parameter(range: 0...1)
        amount.value = 3
        #expect(amount.clampedValue == 1)
        amount.value = -1
        #expect(amount.clampedValue == 0)
    }
}
