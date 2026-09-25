import Foundation
import CoreVideo
import CoreGraphics
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

/// A per-frame snapshot for a live watching view: is a face in frame, where it is,
/// and how close this frame scored to the enrolled owner. Emitted often (every
/// processed frame), unlike `RecognitionStatus`, which only changes on transitions.
public struct RecognitionUpdate: Sendable {
    public var status: RecognitionStatus
    public var facePresent: Bool
    /// Face box normalised to 0…1 in image space, top-left origin (nil if no face).
    public var faceBoxNormalized: CGRect?
    /// Source image aspect ratio (width / height), for overlay mapping.
    public var imageAspect: CGFloat
    /// Best cosine similarity to the gallery this frame; may be below threshold,
    /// nil when it could not be computed (no model, no enrollment, low quality).
    public var score: Double?
    public var threshold: Double
    public var blinkCount: Int
    public var requireLiveness: Bool
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
    private var frameTick = 0

    public let action: RecognitionAction

    /// Called whenever the reported status changes, on the calling (frame) queue.
    public var onStatusChange: ((RecognitionStatus) -> Void)?
    /// Called for every processed frame with live detail for a watching view.
    public var onUpdate: ((RecognitionUpdate) -> Void)?

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

    private var canScore: Bool {
        guard embedder.isAvailable, let t = template, !t.isEmpty else { return false }
        return t.isCompatible(withModel: embedder.modelIdentifier, dimension: embedder.dimension)
    }

    /// Process one camera frame. Detection and scoring run at half the frame rate
    /// to save power; the preview layer stays smooth regardless. Emits a live
    /// `onUpdate` for the watching view and advances the recognition state machine.
    public func process(_ pixelBuffer: CVPixelBuffer) {
        if case .idle = status { return }        // not watching
        frameTick &+= 1
        if frameTick % 2 != 0 { return }         // ~15 fps of work at a 30 fps camera

        let w = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let h = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        let aspect = h > 0 ? w / h : 1

        let faces = detector.detect(in: pixelBuffer)
        guard let face = faces.max(by: { $0.area < $1.area }) else {
            consecutiveMatches = 0
            if case .recognized = status { status = .searching }
            emit(facePresent: false, box: nil, aspect: aspect, score: nil)
            return
        }

        let box = w > 0 && h > 0
            ? CGRect(x: face.boundingBox.minX / w, y: face.boundingBox.minY / h,
                     width: face.boundingBox.width / w, height: face.boundingBox.height / h)
            : nil

        // Track blinks for the liveness gate.
        if let ear = Liveness.eyeAspectRatio(face.leftEyePoints)
            ?? Liveness.eyeAspectRatio(face.rightEyePoints) {
            blink.process(ear: ear)
        }

        // Quality gate: we still show the box, but don't score a poor frame.
        if let q = face.quality, q < config.minFaceQuality {
            emit(facePresent: true, box: box, aspect: aspect, score: nil)
            return
        }

        var score: Double?
        if canScore, let template,
           let aligned = aligner.alignedPixelBuffer(from: face, in: pixelBuffer),
           let probe = try? embedder.embed(aligned) {
            let best = matcher.bestMatch(probe: probe, gallery: template.embeddings)?.score
            score = best
            let matched = (best ?? -1) >= config.cosineThreshold
            let livenessOK = !config.requireLiveness || blink.blinkCount > 0
            if matched && livenessOK {
                consecutiveMatches += 1
                if consecutiveMatches >= config.confirmingFrames {
                    if !isRecognized { status = .recognized(score: best ?? 0) }
                    perform(action)
                }
            } else {
                consecutiveMatches = 0
                if case .recognized = status { status = .searching }
            }
        }

        emit(facePresent: true, box: box, aspect: aspect, score: score)
    }

    private var isRecognized: Bool {
        if case .recognized = status { return true }
        return false
    }

    private func emit(facePresent: Bool, box: CGRect?, aspect: CGFloat, score: Double?) {
        onUpdate?(RecognitionUpdate(
            status: status,
            facePresent: facePresent,
            faceBoxNormalized: box,
            imageAspect: aspect,
            score: score,
            threshold: config.cosineThreshold,
            blinkCount: blink.blinkCount,
            requireLiveness: config.requireLiveness
        ))
    }

    /// The single seam where a recognition turns into an effect. v1: nothing.
    private func perform(_ action: RecognitionAction) {
        switch action {
        case .doNothing:
            break // intentionally no side effect
        }
    }
}
