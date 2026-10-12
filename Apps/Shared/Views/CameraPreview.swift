import AVFoundation
import SwiftUI

/// The live camera image, whole: the view's shape should match the camera's
/// frame, so nothing is cut off and an overlay can mark the kept region.
struct CameraPreview: NSViewRepresentable {

    let session: AVCaptureSession

    func makeNSView(context: Context) -> PreviewView {
        PreviewView(session: session)
    }

    func updateNSView(_ nsView: PreviewView, context: Context) {}

    final class PreviewView: NSView {

        init(session: AVCaptureSession) {
            super.init(frame: .zero)
            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspect
            layer.backgroundColor = NSColor.black.cgColor
            self.layer = layer
            wantsLayer = true
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not used")
        }
    }
}
