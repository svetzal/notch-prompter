import NotchPrompterKit
import SwiftUI

/// Permission notices, the preview, and the device pickers.
struct CameraSection: View {

    let capture: CaptureModel

    var body: some View {
        Section("Camera") {
            ForEach(capture.access.notices, id: \.title) { notice in
                AccessNoticeView(notice: notice) { capture.openPrivacySettings(for: notice.medium) }
            }
            if capture.access.canUseCamera {
                CameraPreview(session: capture.gateway.session)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
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
