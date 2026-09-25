import Foundation
import CoreVideo
import FaceUnlockCore

/// What the pipeline currently believes about the scene. Reported to the app for
/// the menu-bar status; it carries no action of its own.
public enum RecognitionStatus: Sendable, Equatable {
    case idle                 // not watching
    case modelMissing         // no embedding model installed
    case notEnrolled          // model present, but no enrolled face
    case searching            // watching, no confirmed match yet
    case recognized(score: Double)
}

/// Runs the full recognise-the-owner pipeline on incoming frames and reports
/// status. On a confirmed recognition it consults `RecognitionAction`, which in
/// v1 is `.doNothing`.
public final class RecognitionEngine {

    private let detector: FaceDetector
    private let aligner: FaceAligner
    private let embedder: FaceEmbedder
    private var matcher: FaceMatcher
    private var config: RecognitionConfig
    private var blink = BlinkDetector()

    private var template: FaceTemplate?
    private var consecutiveMatches = 0

    public let action: RecognitionAction

    /// Called whenever the reported status changes, on the calling (frame) queue.
    public var onStatusChange: ((RecognitionStatus) -> Void)?

    public private(set) var status: RecognitionStatus = .idle {
        didSet { if status != oldValue { onStatusChange?(status) } }
    }

    public init(embedder: FaceEmbedder,
                template: FaceTemplate?,
                config: RecognitionConfig = .default,
                action: RecognitionAction = .doNothing) {
        self.detector = FaceDetector()
        self.aligner = FaceAligner()
        self.embedder = embedder
        self.template = template
        self.config = config
        self.matcher = FaceMatcher(threshold: config.cosineThreshold)
        self.action = action
    }

    /// Move to the watching state and compute the initial status.
    public func begin() {
        blink.reset()
        consecutiveMatches = 0
        status = initialStatus()
    }

    public func end() {
        status = .idle
    }

    private func initialStatus() -> RecognitionStatus {
        if !embedder.isAvailable { return .modelMissing }
        guard let template, !template.isEmpty,
              template.isCompatible(withModel: embedder.modelIdentifier, dimension: embedder.dimension)
        else { return .notEnrolled }
        return .searching
    }

    /// Process one camera frame. Cheap to call per frame; it early-outs unless we
    /// are actually watching with a usable model and enrollment.
    public func process(_ pixelBuffer: CVPixelBuffer) {
        switch status {
        case .idle, .modelMissing, .notEnrolled:
            return
        case .searching, .recognized:
            break
        }
        guard let template else { return }

        let faces = detector.detect(in: pixelBuffer)
        guard let face = faces.max(by: { $0.area < $1.area }) else {
            reset(); return
        }

        if let q = face.quality, q < config.minFaceQuality { return }

        // Liveness: accumulate blink evidence (does not gate the do-nothing v1
        // hard, but is tracked so the strict path is ready).
        if let ear = Liveness.eyeAspectRatio(face.leftEyePoints)
            ?? Liveness.eyeAspectRatio(face.rightEyePoints) {
            blink.process(ear: ear)
        }

        guard let aligned = aligner.alignedPixelBuffer(from: face, in: pixelBuffer),
              let probe = try? embedder.embed(aligned) else {
            return
        }

        let matched = matcher.isMatch(probe: probe, gallery: template.embeddings)
        let livenessOK = !config.requireLiveness || blink.blinkCount > 0
        guard matched, livenessOK else { reset(); return }

        consecutiveMatches += 1
        guard consecutiveMatches >= config.confirmingFrames else { return }

        let score = matcher.bestMatch(probe: probe, gallery: template.embeddings)?.score ?? 0
        status = .recognized(score: score)
        perform(action)
    }

    private func reset() {
        consecutiveMatches = 0
        if case .searching = status { return }
        if embedder.isAvailable, let t = template, !t.isEmpty { status = .searching }
    }

    /// The single seam where a recognition turns into an effect. v1: nothing.
    private func perform(_ action: RecognitionAction) {
        switch action {
        case .doNothing:
            break // intentionally no side effect
        }
    }
}
