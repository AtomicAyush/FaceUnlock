import SwiftUI
import AVFoundation

/// A live camera preview backed by `AVCaptureVideoPreviewLayer`, wrapped for SwiftUI.
/// `mirrored` flips it horizontally so the front camera reads like a mirror.
struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    var mirrored: Bool = true

    func makeNSView(context: Context) -> PreviewNSView {
        let view = PreviewNSView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.applyMirror(mirrored)
        return view
    }

    func updateNSView(_ nsView: PreviewNSView, context: Context) {
        nsView.previewLayer.session = session
        nsView.applyMirror(mirrored)
    }

    final class PreviewNSView: NSView {
        let previewLayer = AVCaptureVideoPreviewLayer()

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer = CALayer()
            layer?.addSublayer(previewLayer)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        func applyMirror(_ mirrored: Bool) {
            guard let connection = previewLayer.connection,
                  connection.isVideoMirroringSupported else { return }
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = mirrored
        }

        override func layout() {
            super.layout()
            previewLayer.frame = bounds
        }
    }
}
