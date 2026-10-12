import NotchPrompterKit
import SwiftUI

/// Permission notices, the preview, the video format, the device pickers,
/// and the microphone mode.
struct CameraSection: View {

    let capture: CaptureModel
    /// A recorded take is under way, so its format holds still.
    let isTakeInProgress: Bool

    var body: some View {
        Section("Camera") {
            ForEach(capture.access.notices, id: \.title) { notice in
                AccessNoticeView(notice: notice) { capture.openPrivacySettings(for: notice.medium) }
            }
            if capture.access.canUseCamera {
                CameraPreview(session: capture.gateway.session)
                    .overlay {
                        if let crop = capture.previewCrop, crop.needsCrop {
                            KeptRegionOverlay(keptRegion: crop.normalizedRect)
                        }
                    }
                    .aspectRatio(previewAspectRatio, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Picker("Format", selection: formatSelection) {
                    ForEach(VideoFormat.allCases) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(isTakeInProgress || capture.isConfigurationLocked)
                .help("The shape of the next take: Horizontal is 16:9, Vertical is 9:16, cut from the centre of the camera")
            }
            Picker("Camera", selection: cameraSelection) {
                ForEach(capture.cameras) { camera in
                    Text(camera.kind == .continuityCamera ? "\(camera.name) (iPhone)" : camera.name)
                        .tag(Optional(camera.id))
                }
            }
            .disabled(!capture.access.canUseCamera || capture.isConfigurationLocked)
            Picker("Microphone", selection: microphoneSelection) {
                ForEach(capture.microphones) { microphone in
                    Text(microphone.name).tag(Optional(microphone.id))
                }
            }
            .disabled(!capture.access.canUseMicrophone || capture.isConfigurationLocked)
            MicrophoneModeRow(mode: capture.microphoneMode)
            Button("Open Microphone Modes…") { capture.showMicrophoneModesPanel() }
                .help("Open the system Microphone Modes panel: Standard, Voice Isolation, and Wide Spectrum")
        }
    }

    // The pickers show the device in use and record a choice when changed.
    // Reading the device in use, not the stored choice, keeps a disconnected
    // camera remembered without leaving the picker blank.

    private var cameraSelection: Binding<String?> {
        Binding(get: { capture.activeCameraID }, set: { capture.preferredCameraID = $0 })
    }

    private var microphoneSelection: Binding<String?> {
        Binding(get: { capture.activeMicrophoneID }, set: { capture.preferredMicrophoneID = $0 })
    }

    private var formatSelection: Binding<VideoFormat> {
        Binding(get: { capture.videoFormat }, set: { capture.videoFormat = $0 })
    }

    /// The camera's own shape, so the whole frame shows; 16:9 until it is known.
    private var previewAspectRatio: CGFloat {
        guard let size = capture.cameraSize, size.width > 0, size.height > 0 else { return 16 / 9 }
        return CGFloat(size.width) / CGFloat(size.height)
    }
}

/// Dims the part of the camera's frame a take will not keep, and outlines
/// the part it will, so the presenter can frame themself for the format.
private struct KeptRegionOverlay: View {

    /// The kept region as fractions of the frame, origin top left.
    let keptRegion: CGRect

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let kept = CGRect(
                x: keptRegion.minX * size.width,
                y: keptRegion.minY * size.height,
                width: keptRegion.width * size.width,
                height: keptRegion.height * size.height
            )
            ZStack {
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: size))
                    path.addRect(kept)
                }
                .fill(.black.opacity(0.6), style: FillStyle(eoFill: true))
                Path { path in path.addRect(kept.insetBy(dx: 0.5, dy: 0.5)) }
                    .stroke(.white.opacity(0.85), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The system microphone mode in use. When it is not the mode chosen in
/// Control Center, the row says so in orange rather than hiding it.
private struct MicrophoneModeRow: View {

    let mode: MicrophoneModePresentation

    var body: some View {
        LabeledContent {
            Text(mode.label)
                .foregroundStyle(mode.isMismatched ? .orange : .secondary)
        } label: {
            Text("Mic Mode")
            if let note = mode.note {
                Text(note)
            }
        }
        .help("Set in Control Center. Notch Prompter can show the mode but not change it.")
    }
}

private struct AccessNoticeView: View {

    let notice: CaptureAccess.Notice
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(notice.title, systemImage: notice.medium == .camera ? "video.slash" : "mic.slash")
                .font(.headline)
                .foregroundStyle(.orange)
            Text(notice.detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if notice.canOpenSettings {
                Button("Open Privacy Settings", action: openSettings)
            }
        }
        .padding(.vertical, 4)
    }
}
