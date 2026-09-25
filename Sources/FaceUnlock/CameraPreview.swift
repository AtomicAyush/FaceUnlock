import SwiftUI
import AVFoundation

/// A live camera preview backed by `AVCaptureVideoPreviewLayer`, wrapped for SwiftUI.
/// `mirrored` flips it horizontally so the front camera reads like a mirror.
struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    var mirrored: Bool = true

    func makeNSView(context: Context) -> PreviewNSView {
        let view = PreviewNSView()
        view.previewLayer.videoGravity = .resizeAspectFill
        view.attach(session: session, mirrored: mirrored)
        return view
    }

    func updateNSView(_ nsView: PreviewNSView, context: Context) {
        nsView.attach(session: session, mirrored: mirrored)
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

        /// Attach the session and set mirroring, but only when something actually
        /// changed — re-assigning the session mutates its connection set, which we
        /// must not do on every SwiftUI update. Runs on the main thread.
        func attach(session: AVCaptureSession, mirrored: Bool) {
            if previewLayer.session !== session {
                previewLayer.session = session
            }
            if let connection = previewLayer.connection, connection.isVideoMirroringSupported {
                if connection.automaticallyAdjustsVideoMirroring {
                    connection.automaticallyAdjustsVideoMirroring = false
                }
                if connection.isVideoMirrored != mirrored {
                    connection.isVideoMirrored = mirrored
                }
            }
        }

        override func layout() {
            super.layout()
            previewLayer.frame = bounds
        }
    }
}
