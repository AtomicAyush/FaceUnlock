import Foundation

/// Tunable thresholds for the recognition pipeline. Values are conservative
/// defaults; the enrollment step can tighten `cosineThreshold` from the owner's
/// own genuine-score distribution later.
public struct RecognitionConfig: Codable, Sendable, Equatable {
    /// Minimum cosine similarity for a positive identification.
    public var cosineThreshold: Double
    /// Minimum Vision face-capture-quality score (0…1) before a frame is used.
    public var minFaceQuality: Float
    /// Require a blink (or other liveness cue) before accepting a recognition.
    public var requireLiveness: Bool
    /// How many recent frames must agree before recognition is declared, to
    /// smooth out single-frame flukes.
    public var confirmingFrames: Int

    public init(
        cosineThreshold: Double = 0.363,
        minFaceQuality: Float = 0.35,
        requireLiveness: Bool = true,
        confirmingFrames: Int = 3
    ) {
        self.cosineThreshold = cosineThreshold
        self.minFaceQuality = minFaceQuality
        self.requireLiveness = requireLiveness
        self.confirmingFrames = confirmingFrames
    }

    public static let `default` = RecognitionConfig()
}

/// What the app does when it recognises the owner. v1 ships as `.doNothing`:
/// the recognition pipeline runs end to end and takes no action. This enum is
/// the single seam where a future action would attach.
public enum RecognitionAction: String, Codable, Sendable, CaseIterable {
    /// Recognise, update the menu-bar status, and otherwise do nothing.
    case doNothing
}
