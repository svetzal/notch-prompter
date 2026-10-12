import Foundation

/// The presenter's voice clean-up chain: installed Audio Unit effects, in
/// the order a take's audio goes through them.
///
/// The app runs the chain over each take after it is recorded, never live.
/// Each entry keeps the plug-in's own settings as an opaque blob, which only
/// the plug-in can read.
public struct VoiceChain: Codable, Equatable, Sendable {

    public struct Entry: Codable, Equatable, Identifiable, Sendable {
        public let id: UUID
        public let component: AudioUnitComponent
        /// A bypassed plug-in stays in the chain, with its settings, but does
        /// not process.
        public var isBypassed: Bool
        /// The plug-in's settings, as the plug-in saved them (its full state,
        /// as a property list). `nil` until the settings are first saved, so
        /// the plug-in starts from its defaults.
        public var state: Data?

        public init(id: UUID, component: AudioUnitComponent, isBypassed: Bool = false, state: Data? = nil) {
            self.id = id
            self.component = component
            self.isBypassed = isBypassed
            self.state = state
        }
    }

    /// Whether takes are cleaned up. Turning the chain off keeps its plug-ins.
    public var isEnabled: Bool
    public private(set) var entries: [Entry]

    public init(isEnabled: Bool = false, entries: [Entry] = []) {
        self.isEnabled = isEnabled
        self.entries = entries
    }

    /// The entries that process audio, in order.
    public var activeEntries: [Entry] {
        entries.filter { !$0.isBypassed }
    }

    /// Whether a new take goes through the chain: it is on, and at least one
    /// plug-in is not bypassed.
    public var cleansTakes: Bool {
        isEnabled && !activeEntries.isEmpty
    }

    /// One line for the window, for example `AUPeakLimiter → RX 10 De-ess`.
    public var summary: String {
        guard isEnabled else { return "Off" }
        guard !entries.isEmpty else { return "No plug-ins" }
        let active = activeEntries
        guard !active.isEmpty else { return "All plug-ins bypassed" }
        let names = active.map(\.component.name).joined(separator: " → ")
        let bypassed = entries.count - active.count
        return bypassed == 0 ? names : "\(names) (\(bypassed) bypassed)"
    }

    // MARK: - Editing

    /// Puts `component` at the end of the chain, active and at its default
    /// settings, and returns the new entry's identifier.
    @discardableResult
    public mutating func add(_ component: AudioUnitComponent, id: UUID = UUID()) -> UUID {
        entries.append(Entry(id: id, component: component))
        return id
    }

    public mutating func remove(_ id: UUID) {
        entries.removeAll { $0.id == id }
    }

    /// Moves the entries at `source` to before the entry at `destination`, as
    /// a list drag does: `destination` is an offset in the order before the
    /// move, and may be `entries.count` for the end.
    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.filter(entries.indices.contains).map { entries[$0] }
        let insertion = destination - source.count(in: 0..<destination)
        entries = entries.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        entries.insert(contentsOf: moving, at: min(max(0, insertion), entries.count))
    }

    public mutating func setBypassed(_ isBypassed: Bool, for id: UUID) {
        update(id) { $0.isBypassed = isBypassed }
    }

    public mutating func setState(_ state: Data?, for id: UUID) {
        update(id) { $0.state = state }
    }

    private mutating func update(_ id: UUID, _ change: (inout Entry) -> Void) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        change(&entries[index])
    }
}
