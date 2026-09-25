import Foundation
import AVFoundation
import CoreVideo
import Combine
import FaceUnlockCore
import FaceUnlockVision

/// Drives the enrollment window: runs a preview camera, tracks whether a usable
/// face is in frame, and collects a small gallery of embeddings to save as the
/// owner's `FaceTemplate`. Needs the embedding model; without it, capture is
/// disabled and the view explains why.
@MainActor
final class EnrollmentModel: ObservableObject {

    let targetSamples = 5

    @Published private(set) var sampleCount = 0
    @Published private(set) var faceInFrame = false
    @Published private(set) var message = ""
    @Published private(set) var isSaved = false

    var previewSession: AVCaptureSession { camera.session }
    var canCapture: Bool { embedder.isAvailable && faceInFrame && sampleCount < targetSamples }
    var isComplete: Bool { sampleCount >= targetSamples }

    private let camera = CameraController()
    private let detector = FaceDetector()
    private let aligner = FaceAligner()
    private let embedder: FaceEmbedder
    private let store: TemplateStore?

    private var embeddings: [[Float]] = []

    // Latest frame + its largest face, guarded for capture-on-demand.
    private let lock = NSLock()
    private var latestFrame: CVPixelBuffer?
    private var latestFace: DetectedFace?

    init(embedder: FaceEmbedder, store: TemplateStore?) {
        self.embedder = embedder
        self.store = store
        if !embedder.isAvailable {
            message = "The face model isn't installed yet, so enrollment is paused. See docs/MODEL.md."
        } else {
            message = "Center your face in the frame, then capture \(targetSamples) shots from slightly different angles."
        }
    }

    func start() {
        camera.onFrame = { [weak self] buffer in self?.ingest(buffer) }
        Task { @MainActor in
            guard await CameraController.requestAccess() else {
                self.message = "Camera access is off. Turn it on in System Settings → Privacy & Security → Camera."
                return
            }
            do {
                if !self.camera.isConfigured { try self.camera.configure() }
                self.camera.start()
            } catch {
                self.message = "Could not start the camera: \(error)"
            }
        }
    }

    func stop() {
        camera.stop()
    }

    private func ingest(_ buffer: CVPixelBuffer) {
        let faces = detector.detect(in: buffer)
        let face = faces.max(by: { $0.area < $1.area })
        lock.lock()
        latestFrame = buffer
        latestFace = face
        lock.unlock()

        let present = face != nil
        Task { @MainActor in
            if self.faceInFrame != present { self.faceInFrame = present }
        }
    }

    func captureSample() {
        guard embedder.isAvailable else { return }
        lock.lock()
        let frame = latestFrame
        let face = latestFace
        lock.unlock()

        guard let frame, let face else {
            message = "Hold still — no face detected right now."
            return
        }
        guard let aligned = aligner.alignedPixelBuffer(from: face, in: frame),
              let embedding = try? embedder.embed(aligned) else {
            message = "Couldn't read that shot — try again."
            return
        }
        embeddings.append(embedding)
        sampleCount = embeddings.count
        message = isComplete
            ? "Got all \(targetSamples). Save to finish."
            : "Captured \(sampleCount) of \(targetSamples). Turn your head a little and capture again."
    }

    func save() {
        guard isComplete, embedder.isAvailable else { return }
        let template = FaceTemplate(
            embeddings: embeddings,
            modelIdentifier: embedder.modelIdentifier,
            dimension: embedder.dimension,
            createdAt: nowDate()
        )
        do {
            try store?.save(template)
            isSaved = true
            message = "Saved. FaceUnlock can now recognize you."
        } catch {
            message = "Could not save enrollment: \(error)"
        }
    }

    func reset() {
        embeddings.removeAll()
        sampleCount = 0
        isSaved = false
        message = "Cleared. Capture \(targetSamples) shots again."
    }

    /// Isolated so the timestamp source is obvious and swappable in tests.
    private func nowDate() -> Date { Date() }
}
