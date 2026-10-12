import NotchPrompterKit
import SwiftUI

/// Permission notices, the preview, and the device pickers.
struct CameraSection: View {

    @Bindable var capture: CaptureModel

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
            Picker("Camera", selection: $capture.preferredCameraID) {
                ForEach(capture.cameras) { camera in
                    Text(camera.kind == .continuityCamera ? "\(camera.name) (iPhone)" : camera.name)
                        .tag(Optional(camera.id))
                }
            }
            .disabled(!capture.access.canUseCamera || capture.isConfigurationLocked)
            Picker("Microphone", selection: $capture.preferredMicrophoneID) {
                ForEach(capture.microphones) { microphone in
                    Text(microphone.name).tag(Optional(microphone.id))
                }
            }
            .disabled(!capture.access.canUseMicrophone || capture.isConfigurationLocked)
        }
        .onAppear(perform: syncPickers)
        .onChange(of: capture.activeCameraID) { syncPickers() }
        .onChange(of: capture.activeMicrophoneID) { syncPickers() }
    }

    /// Shows the device actually in use when the stored choice is missing.
    private func syncPickers() {
        if capture.preferredCameraID.map({ id in !capture.cameras.contains { $0.id == id } }) ?? true,
           let active = capture.activeCameraID {
            capture.preferredCameraID = active
        }
        if capture.preferredMicrophoneID.map({ id in !capture.microphones.contains { $0.id == id } }) ?? true,
           let active = capture.activeMicrophoneID {
            capture.preferredMicrophoneID = active
        }
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
