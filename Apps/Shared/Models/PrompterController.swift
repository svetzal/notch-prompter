import AppKit
import NotchPrompterKit
import Observation

/// Starts and stops recording on behalf of a take.
///
/// The prompter does not know about cameras. The capture layer conforms to
/// this, and the controller carries out the Kit's `.startRecording` and
/// `.stopRecording` commands through it.
@MainActor
protocol TakeRecorder: AnyObject {
    /// Begins writing a movie for the take. Reports the end through `PrompterController.recordingDidEnd()`.
    func startRecording(scriptTitle: String?)
    func stopRecording()
}

/// Runs the prompter: the panel, the keys, the countdown, and the take state.
///
/// The decisions belong to the Kit's `TakeSession`. This class executes its
/// commands against AppKit and keeps the panel's layout in step with the
/// script and the settings.
@MainActor
@Observable
final class PrompterController {

    private(set) var session: TakeSession
    private(set) var displays: [DisplayInfo] = []

    var settings: PrompterSettings {
        didSet { settingsDidChange(from: oldValue) }
    }

    /// The display chosen in the window, kept even while it is disconnected.
    var preferredDisplayID: CGDirectDisplayID? {
        didSet {
            defaults.set(preferredDisplayID.map { Int($0) }, forKey: Keys.display)
            repositionPanel()
        }
    }

    /// The title of the script being read, for naming recordings.
    var scriptTitle: String?

    @ObservationIgnored weak var recorder: TakeRecorder?

    @ObservationIgnored private var document = PrompterDocument(blocks: [])
    @ObservationIgnored private var panel: PrompterPanel?
    @ObservationIgnored private let keyMonitor = PrompterKeyMonitor()
    @ObservationIgnored private var countdownTask: Task<Void, Never>?
    @ObservationIgnored private let defaults: UserDefaults

    private enum Keys {
        static let speed = "prompter.wordsPerMinute"
        static let fontSize = "prompter.fontSize"
        static let width = "prompter.width"
        static let lines = "prompter.visibleLines"
        static let countdown = "prompter.countdownSeconds"
        static let display = "prompter.displayID"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = PrompterSettings(
            wordsPerMinute: defaults.object(forKey: Keys.speed) as? Double ?? 140,
            fontSize: defaults.object(forKey: Keys.fontSize) as? Double ?? 30,
            width: defaults.object(forKey: Keys.width) as? Double ?? 460,
            visibleLines: defaults.object(forKey: Keys.lines) as? Int ?? 4,
            countdownSeconds: defaults.object(forKey: Keys.countdown) as? Int ?? 3
        )
        settings = stored
        session = TakeSession(
            layout: PrompterLayout(lines: []),
            wordsPerMinute: stored.wordsPerMinute,
            countdown: TimeInterval(stored.countdownSeconds)
        )
        preferredDisplayID = (defaults.object(forKey: Keys.display) as? Int).map { CGDirectDisplayID($0) }
        displays = Displays.current()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensDidChange() }
        }
    }

    // MARK: - Derived state

    /// The display the prompter goes on: the chosen one, else one with a notch, else the main one.
    var activeDisplay: DisplayInfo? {
        let notched = displays.first(where: \.hasNotch)?.id
        let id = PreferredSelection.resolve(
            preferred: preferredDisplayID,
            available: displays.map(\.id),
            fallbacks: [notched]
        )
        return displays.first { $0.id == id }
    }

    var isPrompterVisible: Bool { session.isPrompterVisible }

    /// Where the panel goes on the active display, and how far down its text starts.
    var placement: PrompterPlacement? {
        activeDisplay.map { PrompterPlacement(on: $0.geometry, textArea: settings.textAreaSize) }
    }

    // MARK: - Script

    func setDocument(_ document: PrompterDocument) {
        guard document != self.document else { return }
        self.document = document
        session.relayout(makeLayout(), at: .now)
    }

    /// A different script starts from its top, unless a run is under way.
    func rewindIfIdle() {
        if session.canBegin {
            session.rewindToStart(at: .now)
        }
    }

    private func makeLayout() -> PrompterLayout {
        let fontSize = settings.fontSize
        return PrompterLayout(document: document, width: settings.textWidth) {
            TextMeasurer.width(of: $0, fontSize: fontSize)
        }
    }

    // MARK: - Actions

    func togglePrompter() {
        if session.phase == .hidden {
            perform(session.showPrompter())
        } else if session.phase == .ready {
            perform(session.stop(at: .now))
        }
    }

    func rehearse() {
        perform(session.begin(.rehearsal, at: .now))
    }

    func record() {
        perform(session.begin(.recording, at: .now))
    }

    func stop() {
        perform(session.stop(at: .now))
    }

    /// The recorder reports that the movie file closed, for any reason.
    func recordingDidEnd() {
        session.recordingDidEnd(at: .now)
    }

    @discardableResult
    func handle(_ key: PrompterKeyCommand) -> Bool {
        guard session.isPrompterVisible else { return false }
        let now = Date.now
        switch key {
        case .togglePlayback: perform(session.togglePlayback(at: now))
        case .stop: perform(session.stop(at: now))
        case .faster: settings.faster()
        case .slower: settings.slower()
        case .nudgeBack: session.nudge(byLines: -1, at: now)
        case .nudgeForward: session.nudge(byLines: 1, at: now)
        case .previousParagraph: session.jumpToPreviousParagraph(at: now)
        case .nextParagraph: session.jumpToNextParagraph(at: now)
        case .rewindToStart: session.rewindToStart(at: now)
        case .largerText: settings.largerText()
        case .smallerText: settings.smallerText()
        }
        return true
    }

    // MARK: - Carrying out commands

    private func perform(_ commands: [TakeSession.Command]) {
        for command in commands {
            switch command {
            case .showPrompter: showPanel()
            case .hidePrompter: hidePanel()
            case .scheduleCountdownEnd(let endsAt): scheduleCountdownEnd(endsAt)
            case .startRecording: recorder?.startRecording(scriptTitle: scriptTitle)
            case .stopRecording: recorder?.stopRecording()
            }
        }
        if session.phase != .ready, session.phase != .hidden {
            // Typing belongs to the editor until a run starts; then keys belong to the prompter.
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
    }

    private func scheduleCountdownEnd(_ endsAt: Date) {
        countdownTask?.cancel()
        countdownTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, endsAt.timeIntervalSinceNow)))
            guard !Task.isCancelled, let self else { return }
            perform(session.countdownDidEnd(scheduledFor: endsAt, at: .now))
        }
    }

    private func showPanel() {
        if panel == nil {
            panel = PrompterPanel(rootView: PrompterView(controller: self))
        }
        repositionPanel()
        keyMonitor.start(
            claimsKeysFromTextViews: { [weak self] in
                guard let phase = self?.session.phase else { return false }
                return phase != .ready && phase != .hidden
            },
            handler: { [weak self] command in self?.handle(command) ?? false }
        )
    }

    private func hidePanel() {
        countdownTask?.cancel()
        keyMonitor.stop()
        panel?.hide()
    }

    private func repositionPanel() {
        guard session.isPrompterVisible, let panel, let placement else { return }
        panel.show(in: placement.frame)
    }

    private func screensDidChange() {
        displays = Displays.current()
        repositionPanel()
    }

    private func settingsDidChange(from old: PrompterSettings) {
        let now = Date.now
        if settings.wordsPerMinute != old.wordsPerMinute {
            session.setSpeed(settings.wordsPerMinute, at: now)
            defaults.set(settings.wordsPerMinute, forKey: Keys.speed)
        }
        if settings.countdownSeconds != old.countdownSeconds {
            session.countdown = TimeInterval(settings.countdownSeconds)
            defaults.set(settings.countdownSeconds, forKey: Keys.countdown)
        }
        if settings.fontSize != old.fontSize || settings.width != old.width {
            session.relayout(makeLayout(), at: now)
            defaults.set(settings.fontSize, forKey: Keys.fontSize)
            defaults.set(settings.width, forKey: Keys.width)
        }
        if settings.textAreaSize != old.textAreaSize {
            defaults.set(settings.visibleLines, forKey: Keys.lines)
            repositionPanel()
        }
    }
}
