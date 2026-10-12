/// The system video effects the app reports on.
public enum VideoEffect: CaseIterable, Sendable {
    case portrait
    case studioLight
    case backgroundReplacement
    case edgeLight
    case centerStage

    public var title: String {
        switch self {
        case .portrait: "Portrait"
        case .studioLight: "Studio Light"
        case .backgroundReplacement: "Background"
        case .edgeLight: "Edge Light"
        case .centerStage: "Center Stage"
        }
    }
}

/// What AVFoundation says about one effect.
public struct EffectReading: Equatable, Sendable {
    /// The camera's active format can render it.
    public var isSupported: Bool
    /// The system-wide switch (Control Center) is on.
    public var isEnabled: Bool
    /// The effect is in use now. For the camera effects, the camera is
    /// applying it. For Edge Light, the system is drawing it on a screen.
    public var isActive: Bool

    public init(isSupported: Bool, isEnabled: Bool, isActive: Bool) {
        self.isSupported = isSupported
        self.isEnabled = isEnabled
        self.isActive = isActive
    }

    public static let unsupported = EffectReading(isSupported: false, isEnabled: false, isActive: false)
}

/// A raw reading of every effect, as the capture layer observes it.
///
/// The capture layer fills this from AVFoundation's key-value observable
/// properties. ``EffectsPresentation`` turns it into what the window shows.
public struct EffectsSnapshot: Equatable, Sendable {

    public enum CenterStageControl: Equatable, Sendable {
        /// Only Control Center can change it.
        case user
        /// The app has exclusive control. Notch Prompter never asks for this.
        case app
        /// The app and Control Center share control.
        case cooperative
    }

    public var portrait: EffectReading
    public var studioLight: EffectReading
    public var backgroundReplacement: EffectReading
    /// Edge Light is drawn by the system on a display, not by the camera.
    /// Support comes from the camera's active format, but enabled and active
    /// are system-wide: active means the light is showing on a screen now.
    public var edgeLight: EffectReading
    public var centerStage: EffectReading
    public var centerStageControl: CenterStageControl
    /// Reactions are allowed for this app (`reactionEffectsEnabled`).
    public var reactionsEnabled: Bool
    /// The camera can render reactions now (`canPerformReactionEffects`).
    public var canPerformReactions: Bool
    /// `availableReactionTypes`, as raw values.
    public var availableReactions: Set<String>

    public init(
        portrait: EffectReading,
        studioLight: EffectReading,
        backgroundReplacement: EffectReading,
        edgeLight: EffectReading,
        centerStage: EffectReading,
        centerStageControl: CenterStageControl,
        reactionsEnabled: Bool,
        canPerformReactions: Bool,
        availableReactions: Set<String>
    ) {
        self.portrait = portrait
        self.studioLight = studioLight
        self.backgroundReplacement = backgroundReplacement
        self.edgeLight = edgeLight
        self.centerStage = centerStage
        self.centerStageControl = centerStageControl
        self.reactionsEnabled = reactionsEnabled
        self.canPerformReactions = canPerformReactions
        self.availableReactions = availableReactions
    }

    /// The reading with no camera selected.
    public static let noCamera = EffectsSnapshot(
        portrait: .unsupported,
        studioLight: .unsupported,
        backgroundReplacement: .unsupported,
        edgeLight: .unsupported,
        centerStage: .unsupported,
        centerStageControl: .user,
        reactionsEnabled: false,
        canPerformReactions: false,
        availableReactions: []
    )

    public func reading(for effect: VideoEffect) -> EffectReading {
        switch effect {
        case .portrait: portrait
        case .studioLight: studioLight
        case .backgroundReplacement: backgroundReplacement
        case .edgeLight: edgeLight
        case .centerStage: centerStage
        }
    }
}

/// What the effects section of the window shows, derived from a snapshot.
///
/// Apple lets an app switch Center Stage (in cooperative mode) and trigger
/// reactions. Portrait, Studio Light, background replacement, and Edge Light
/// are read-only to apps, so their only control is the system Video Effects
/// panel.
public struct EffectsPresentation: Equatable, Sendable {

    public enum Status: Equatable, Sendable {
        case active
        /// Switched on, but not in use now: this camera is not applying it in
        /// its current state, or (for Edge Light) the system is not showing it.
        case enabledButInactive
        case off
        case unsupported

        public var label: String {
            switch self {
            case .active: "On"
            case .enabledButInactive: "On, not active"
            case .off: "Off"
            case .unsupported: "Not available"
            }
        }
    }

    public enum Control: Equatable, Sendable {
        case toggle(isOn: Bool)
        case systemPanel
        case none
    }

    public struct Row: Equatable, Sendable, Identifiable {
        public let effect: VideoEffect
        public let status: Status
        public let control: Control
        /// A short explanation of the status, when the label alone could mislead.
        public let note: String?
        public var id: String { effect.title }
    }

    public let rows: [Row]
    /// Raw reaction types to offer as buttons, in a friendly order.
    public let reactions: [String]
    /// Why there are no reaction buttons, when there are none.
    public let reactionsUnavailableReason: String?

    public init(_ snapshot: EffectsSnapshot) {
        rows = VideoEffect.allCases.map { effect in
            let reading = snapshot.reading(for: effect)
            let status = Self.status(of: reading)
            return Row(
                effect: effect,
                status: status,
                control: Self.control(for: effect, reading: reading, centerStageControl: snapshot.centerStageControl),
                note: Self.note(for: effect, status: status)
            )
        }
        if !snapshot.reactionsEnabled {
            reactions = []
            reactionsUnavailableReason = "Reactions are turned off for this app."
        } else if !snapshot.canPerformReactions || snapshot.availableReactions.isEmpty {
            reactions = []
            reactionsUnavailableReason = "This camera cannot show reactions in its current mode."
        } else {
            reactions = ReactionNames.ordered(snapshot.availableReactions)
            reactionsUnavailableReason = nil
        }
    }

    static func status(of reading: EffectReading) -> Status {
        if !reading.isSupported { return .unsupported }
        if reading.isActive { return .active }
        return reading.isEnabled ? .enabledButInactive : .off
    }

    /// Edge Light switched on in Control Center but not showing is the
    /// normal state of its Automatic mode in a lit room, not a fault.
    static func note(for effect: VideoEffect, status: Status) -> String? {
        guard effect == .edgeLight, status == .enabledButInactive else { return nil }
        return "In Automatic mode it comes on only in low light. Set it to On in Video Effects to keep it showing."
    }

    static func control(
        for effect: VideoEffect,
        reading: EffectReading,
        centerStageControl: EffectsSnapshot.CenterStageControl
    ) -> Control {
        guard reading.isSupported else { return .none }
        if effect == .centerStage, centerStageControl != .user {
            return .toggle(isOn: reading.isEnabled)
        }
        return .systemPanel
    }
}

/// Display names and ordering for `AVCaptureReactionType` raw values.
public enum ReactionNames {

    /// The order people reach for them, most common first.
    static let preferredOrder = [
        "ReactionThumbsUp", "ReactionThumbsDown", "ReactionHeart", "ReactionBalloons",
        "ReactionConfetti", "ReactionFireworks", "ReactionRain", "ReactionLasers"
    ]

    /// Known reactions in preferred order, then any new ones alphabetically.
    public static func ordered(_ reactions: Set<String>) -> [String] {
        let known = preferredOrder.filter(reactions.contains)
        let unknown = reactions.subtracting(preferredOrder).sorted()
        return known + unknown
    }

    /// `ReactionThumbsUp` becomes "Thumbs Up".
    public static func title(for rawValue: String) -> String {
        let name = rawValue.hasPrefix("Reaction") ? String(rawValue.dropFirst("Reaction".count)) : rawValue
        var words: [String] = []
        for character in name {
            if character.isUppercase || words.isEmpty {
                words.append(String(character))
            } else {
                words[words.count - 1].append(character)
            }
        }
        return words.joined(separator: " ")
    }
}
