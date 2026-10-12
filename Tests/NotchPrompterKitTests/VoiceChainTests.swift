import Foundation
import Testing
@testable import NotchPrompterKit

private let limiter = AudioUnitComponent(
    type: AudioUnitComponent.code("aufx"), subtype: AudioUnitComponent.code("lmtr"),
    manufacturer: AudioUnitComponent.code("appl"), name: "AUPeakLimiter", manufacturerName: "Apple"
)
private let equalizer = AudioUnitComponent(
    type: AudioUnitComponent.code("aufx"), subtype: AudioUnitComponent.code("nbeq"),
    manufacturer: AudioUnitComponent.code("appl"), name: "AUNBandEQ", manufacturerName: "Apple"
)
private let deEsser = AudioUnitComponent(
    type: AudioUnitComponent.code("aufx"), subtype: 0x725A_4530,
    manufacturer: AudioUnitComponent.code("iZtp"), name: "RX 10 De-ess", manufacturerName: "iZotope"
)

private func ids(_ count: Int) -> [UUID] {
    (0..<count).map { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", $0)) ?? UUID() }
}

private func chain(_ components: [AudioUnitComponent], isEnabled: Bool = true) -> VoiceChain {
    var chain = VoiceChain(isEnabled: isEnabled)
    for (component, id) in zip(components, ids(components.count)) {
        chain.add(component, id: id)
    }
    return chain
}

@Suite("Audio Unit components")
struct AudioUnitComponentTests {

    @Test("four-character codes read as text and back", arguments: ["aufx", "lmtr", "appl", "iZtp", "vois"])
    func codes(text: String) {
        #expect(AudioUnitComponent.text(for: AudioUnitComponent.code(text)) == text)
    }

    @Test("a component's codes read type, subtype, manufacturer, as auval prints them")
    func codesText() {
        #expect(limiter.codes == "aufx lmtr appl")
        #expect(deEsser.codes == "aufx rZE0 iZtp")
    }

    @Test("codes with characters that are not printable show as hex")
    func unprintable() {
        #expect(AudioUnitComponent.text(for: 0x0000_0001) == "0x00000001")
    }

    @Test("only effects are offered, sorted by maker then name, without duplicates")
    func offered() {
        let musicEffect = AudioUnitComponent(
            type: AudioUnitComponent.code("aumf"), subtype: 1, manufacturer: 2, name: "Synth FX", manufacturerName: "Maker"
        )
        let offered = AudioUnitComponent.offeredEffects(from: [deEsser, musicEffect, limiter, equalizer, limiter])
        #expect(offered == [equalizer, limiter, deEsser])
    }
}

@Suite("Voice chain")
struct VoiceChainTests {

    @Test("a new chain is off and empty, and cleans nothing")
    func empty() {
        let chain = VoiceChain()
        #expect(!chain.isEnabled)
        #expect(chain.entries.isEmpty)
        #expect(!chain.cleansTakes)
    }

    @Test("added plug-ins go on the end, active, with no saved settings")
    func add() {
        let chain = chain([limiter, equalizer])
        #expect(chain.entries.map(\.component) == [limiter, equalizer])
        #expect(chain.entries.allSatisfy { !$0.isBypassed && $0.state == nil })
    }

    @Test("the same plug-in can be in the chain twice, as separate entries")
    func duplicates() {
        let chain = chain([limiter, limiter])
        #expect(chain.entries.count == 2)
        #expect(Set(chain.entries.map(\.id)).count == 2)
    }

    @Test("removing takes out only that entry")
    func remove() {
        var chain = chain([limiter, equalizer, deEsser])
        chain.remove(chain.entries[1].id)
        #expect(chain.entries.map(\.component) == [limiter, deEsser])
    }

    @Test("moving follows list drag rules: the destination is an offset in the old order", arguments: [
        (IndexSet([0]), 3, [1, 2, 0]),
        (IndexSet([2]), 0, [2, 0, 1]),
        (IndexSet([0]), 2, [1, 0, 2]),
        (IndexSet([0, 2]), 1, [0, 2, 1]),
        (IndexSet([1]), 1, [0, 1, 2])
    ])
    func move(source: IndexSet, destination: Int, expected: [Int]) {
        let components = [limiter, equalizer, deEsser]
        var chain = chain(components)
        chain.move(fromOffsets: source, toOffset: destination)
        #expect(chain.entries.map(\.component) == expected.map { components[$0] })
    }

    @Test("bypassed plug-ins stay in the chain but do not process")
    func bypass() {
        var chain = chain([limiter, equalizer])
        chain.setBypassed(true, for: chain.entries[0].id)
        #expect(chain.entries[0].isBypassed)
        #expect(chain.activeEntries.map(\.component) == [equalizer])
        chain.setBypassed(false, for: chain.entries[0].id)
        #expect(chain.activeEntries.count == 2)
    }

    @Test("a plug-in's settings are kept with its entry")
    func state() {
        var chain = chain([limiter, equalizer])
        let settings = Data([1, 2, 3])
        chain.setState(settings, for: chain.entries[1].id)
        #expect(chain.entries[1].state == settings)
        #expect(chain.entries[0].state == nil)
    }

    @Test("takes are cleaned only when the chain is on and has an active plug-in")
    func cleansTakes() {
        #expect(chain([limiter]).cleansTakes)
        #expect(!chain([limiter], isEnabled: false).cleansTakes)
        #expect(!chain([]).cleansTakes)
        var allBypassed = chain([limiter])
        allBypassed.setBypassed(true, for: allBypassed.entries[0].id)
        #expect(!allBypassed.cleansTakes)
    }

    @Test("the summary names the active plug-ins in order")
    func summary() {
        var withBypass = chain([limiter, equalizer, deEsser])
        withBypass.setBypassed(true, for: withBypass.entries[1].id)
        #expect(chain([limiter, deEsser]).summary == "AUPeakLimiter → RX 10 De-ess")
        #expect(withBypass.summary == "AUPeakLimiter → RX 10 De-ess (1 bypassed)")
        #expect(chain([limiter], isEnabled: false).summary == "Off")
        #expect(chain([]).summary == "No plug-ins")
        var allBypassed = chain([limiter])
        allBypassed.setBypassed(true, for: allBypassed.entries[0].id)
        #expect(allBypassed.summary == "All plug-ins bypassed")
    }

    @Test("a chain survives a JSON round trip, settings included")
    func codable() throws {
        var original = chain([limiter, deEsser])
        original.setBypassed(true, for: original.entries[0].id)
        original.setState(Data("settings".utf8), for: original.entries[1].id)
        let decoded = try JSONDecoder().decode(VoiceChain.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
    }
}
