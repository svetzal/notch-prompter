import Testing
@testable import NotchPrompterKit

@Suite("Capture devices")
struct CaptureDeviceTests {

    @Test("sorts built-in, then Continuity Camera, then external, each by name")
    func sorting() {
        let devices = [
            CaptureDeviceInfo(id: "3", name: "Studio Display Camera", kind: .externalCamera),
            CaptureDeviceInfo(id: "2", name: "Stacey's iPhone Camera", kind: .continuityCamera),
            CaptureDeviceInfo(id: "4", name: "Brio", kind: .externalCamera),
            CaptureDeviceInfo(id: "1", name: "FaceTime HD Camera", kind: .builtInCamera)
        ]
        #expect(CaptureDeviceInfo.sortedForDisplay(devices).map(\.id) == ["1", "2", "4", "3"])
    }
}

@Suite("Capture access")
struct CaptureAccessTests {

    @Test("asks while either permission is undecided")
    func needsRequest() {
        #expect(CaptureAccess(camera: .notDetermined, microphone: .authorized).needsRequest)
        #expect(CaptureAccess(camera: .authorized, microphone: .notDetermined).needsRequest)
        #expect(!CaptureAccess(camera: .denied, microphone: .authorized).needsRequest)
    }

    @Test("says nothing when everything is allowed")
    func allowed() {
        let access = CaptureAccess(camera: .authorized, microphone: .authorized)
        #expect(access.notices.isEmpty)
        #expect(access.canUseCamera && access.canUseMicrophone)
    }

    @Test("a denied camera points to System Settings")
    func deniedCamera() throws {
        let access = CaptureAccess(camera: .denied, microphone: .authorized)
        let notice = try #require(access.notices.first)
        #expect(access.notices.count == 1)
        #expect(notice.medium == .camera)
        #expect(notice.canOpenSettings)
        #expect(!access.canUseCamera)
    }

    @Test("a denied microphone warns that takes have no sound")
    func deniedMicrophone() throws {
        let notice = try #require(CaptureAccess(camera: .authorized, microphone: .denied).notices.first)
        #expect(notice.medium == .microphone)
        #expect(notice.detail.contains("without sound"))
    }

    @Test("restricted access does not offer a settings button")
    func restricted() {
        let notices = CaptureAccess(camera: .restricted, microphone: .restricted).notices
        #expect(notices.map(\.medium) == [.camera, .microphone])
        #expect(notices.allSatisfy { !$0.canOpenSettings })
    }
}

@Suite("Effects presentation")
struct EffectsPresentationTests {

    func snapshot(
        portrait: EffectReading = .unsupported,
        edgeLight: EffectReading = .unsupported,
        centerStage: EffectReading = .unsupported,
        centerStageControl: EffectsSnapshot.CenterStageControl = .cooperative,
        reactionsEnabled: Bool = true,
        canPerformReactions: Bool = true,
        availableReactions: Set<String> = []
    ) -> EffectsSnapshot {
        EffectsSnapshot(
            portrait: portrait,
            studioLight: .unsupported,
            backgroundReplacement: .unsupported,
            edgeLight: edgeLight,
            centerStage: centerStage,
            centerStageControl: centerStageControl,
            reactionsEnabled: reactionsEnabled,
            canPerformReactions: canPerformReactions,
            availableReactions: availableReactions
        )
    }

    func row(_ effect: VideoEffect, in presentation: EffectsPresentation) -> EffectsPresentation.Row? {
        presentation.rows.first { $0.effect == effect }
    }

    @Test("lists every effect in a fixed order")
    func order() {
        let presentation = EffectsPresentation(.noCamera)
        #expect(presentation.rows.map(\.effect) == [
            .portrait, .studioLight, .backgroundReplacement, .edgeLight, .centerStage
        ])
    }

    @Test("status follows support, then activity, then the system switch", arguments: [
        (EffectReading(isSupported: false, isEnabled: true, isActive: true), EffectsPresentation.Status.unsupported),
        (EffectReading(isSupported: true, isEnabled: true, isActive: true), .active),
        (EffectReading(isSupported: true, isEnabled: true, isActive: false), .enabledButInactive),
        (EffectReading(isSupported: true, isEnabled: false, isActive: false), .off)
    ])
    func status(reading: EffectReading, expected: EffectsPresentation.Status) {
        #expect(row(.portrait, in: EffectsPresentation(snapshot(portrait: reading)))?.status == expected)
    }

    @Test("read-only effects offer only the system panel")
    func readOnlyEffects() {
        let reading = EffectReading(isSupported: true, isEnabled: false, isActive: false)
        #expect(row(.portrait, in: EffectsPresentation(snapshot(portrait: reading)))?.control == .systemPanel)
    }

    @Test("Edge Light status follows format support, the Control Center switch, and whether it is showing", arguments: [
        (EffectReading(isSupported: false, isEnabled: false, isActive: false), EffectsPresentation.Status.unsupported),
        (EffectReading(isSupported: true, isEnabled: false, isActive: false), .off),
        (EffectReading(isSupported: true, isEnabled: true, isActive: false), .enabledButInactive),
        (EffectReading(isSupported: true, isEnabled: true, isActive: true), .active)
    ])
    func edgeLightStatus(reading: EffectReading, expected: EffectsPresentation.Status) {
        #expect(row(.edgeLight, in: EffectsPresentation(snapshot(edgeLight: reading)))?.status == expected)
    }

    @Test("Edge Light is read-only, so it offers only the system panel")
    func edgeLightControl() {
        let reading = EffectReading(isSupported: true, isEnabled: true, isActive: true)
        #expect(row(.edgeLight, in: EffectsPresentation(snapshot(edgeLight: reading)))?.control == .systemPanel)
        #expect(row(.edgeLight, in: EffectsPresentation(.noCamera))?.control == EffectsPresentation.Control.none)
    }

    @Test("Edge Light switched on but not showing explains Automatic mode")
    func edgeLightNotShowing() {
        let reading = EffectReading(isSupported: true, isEnabled: true, isActive: false)
        let edgeLight = row(.edgeLight, in: EffectsPresentation(snapshot(edgeLight: reading)))
        #expect(edgeLight?.status.label == "On, not active")
        #expect(edgeLight?.note?.contains("low light") == true)
        #expect(edgeLight?.note?.contains("Set it to On in Video Effects") == true)
    }

    @Test("Edge Light has no note when the label says it all", arguments: [
        EffectReading(isSupported: true, isEnabled: true, isActive: true),
        EffectReading(isSupported: true, isEnabled: false, isActive: false),
        EffectReading.unsupported
    ])
    func edgeLightNoNote(reading: EffectReading) {
        #expect(row(.edgeLight, in: EffectsPresentation(snapshot(edgeLight: reading)))?.note == nil)
    }

    @Test("other effects switched on but inactive carry no note")
    func otherEffectsNoNote() {
        let reading = EffectReading(isSupported: true, isEnabled: true, isActive: false)
        #expect(row(.portrait, in: EffectsPresentation(snapshot(portrait: reading)))?.note == nil)
    }

    @Test("Center Stage gets a switch under cooperative control")
    func centerStageToggle() {
        let reading = EffectReading(isSupported: true, isEnabled: true, isActive: true)
        let presentation = EffectsPresentation(snapshot(centerStage: reading, centerStageControl: .cooperative))
        #expect(row(.centerStage, in: presentation)?.control == .toggle(isOn: true))
    }

    @Test("Center Stage falls back to the system panel under user control")
    func centerStageUserControl() {
        let reading = EffectReading(isSupported: true, isEnabled: false, isActive: false)
        let presentation = EffectsPresentation(snapshot(centerStage: reading, centerStageControl: .user))
        #expect(row(.centerStage, in: presentation)?.control == .systemPanel)
    }

    @Test("an unsupported effect has no control")
    func unsupportedControl() {
        #expect(row(.centerStage, in: EffectsPresentation(.noCamera))?.control == EffectsPresentation.Control.none)
    }

    @Test("offers available reactions in a friendly order")
    func reactions() {
        let presentation = EffectsPresentation(snapshot(availableReactions: [
            "ReactionLasers", "ReactionThumbsUp", "ReactionHeart", "ReactionSomethingNew"
        ]))
        #expect(presentation.reactions == ["ReactionThumbsUp", "ReactionHeart", "ReactionLasers", "ReactionSomethingNew"])
        #expect(presentation.reactionsUnavailableReason == nil)
    }

    @Test("explains why reactions are missing")
    func noReactions() {
        let off = EffectsPresentation(snapshot(reactionsEnabled: false, availableReactions: ["ReactionHeart"]))
        #expect(off.reactions.isEmpty)
        #expect(off.reactionsUnavailableReason?.contains("turned off") == true)
        let cannot = EffectsPresentation(snapshot(canPerformReactions: false, availableReactions: ["ReactionHeart"]))
        #expect(cannot.reactions.isEmpty)
        #expect(cannot.reactionsUnavailableReason?.contains("cannot show") == true)
    }

    @Test("names reactions from their raw values", arguments: [
        ("ReactionThumbsUp", "Thumbs Up"), ("ReactionHeart", "Heart"), ("Sparkles", "Sparkles")
    ])
    func names(rawValue: String, title: String) {
        #expect(ReactionNames.title(for: rawValue) == title)
    }
}
