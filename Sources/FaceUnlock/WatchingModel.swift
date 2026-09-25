import Foundation
import AVFoundation
import Combine
import FaceUnlockVision

/// Backs the watching window: exposes the live camera session for the preview and
/// the latest `RecognitionUpdate` for the on-screen feedback. It owns neither the
/// camera nor the engine — the AppDelegate does — so the window is just a view
/// onto the recognition already running.
@MainActor
final class WatchingModel: ObservableObject {
    let session: AVCaptureSession

    @Published var status: RecognitionStatus = .searching
    @Published var facePresent = false
    @Published var faceBox: CGRect?          // normalised 0…1, top-left origin
    @Published var imageAspect: CGFloat = 4.0 / 3.0
    @Published var score: Double?
    @Published var threshold: Double = 0.363
    @Published var requireLiveness = true
    @Published var blinkCount = 0

    init(session: AVCaptureSession) {
        self.session = session
    }

    /// Fold a fresh engine update into the published state (call on the main actor).
    func apply(_ u: RecognitionUpdate) {
        status = u.status
        facePresent = u.facePresent
        faceBox = u.faceBoxNormalized
        imageAspect = u.imageAspect
        score = u.score
        threshold = u.threshold
        requireLiveness = u.requireLiveness
        blinkCount = u.blinkCount
    }

    var headline: String {
        switch status {
        case .idle: return "Paused"
        case .modelMissing: return "No face model installed"
        case .notEnrolled: return "No face enrolled yet"
        case .searching: return facePresent ? "Looking for you…" : "Waiting for a face…"
        case .recognized: return "That's you"
        }
    }

    var isRecognized: Bool {
        if case .recognized = status { return true }
        return false
    }

    var awaitingBlink: Bool {
        requireLiveness && blinkCount == 0 && facePresent && !isRecognized
    }
}
