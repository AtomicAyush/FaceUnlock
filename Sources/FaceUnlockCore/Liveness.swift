import Foundation

/// A light, depth-free liveness signal for a 2-D webcam. It is honestly limited:
/// it defeats a still photo held up to the camera, but not a video replay. That
/// limit is inherent to a lens with no depth sensor and is documented, not hidden.
public enum Liveness {

    /// Eye aspect ratio (Soukupová & Čech). Six eye landmarks ordered around the
    /// eye: p0,p3 are the horizontal corners; p1,p5 and p2,p4 are the vertical
    /// pairs. A wide-open eye is ~0.3; a closed eye drops toward ~0.1.
    ///
    ///     EAR = (‖p1−p5‖ + ‖p2−p4‖) / (2·‖p0−p3‖)
    ///
    /// Returns nil if fewer than six points are supplied.
    public static func eyeAspectRatio(_ p: [Point2D]) -> Double? {
        guard p.count >= 6 else { return nil }
        let horizontal = p[0].distance(to: p[3])
        guard horizontal > 1e-9 else { return nil }
        let vertical = p[1].distance(to: p[5]) + p[2].distance(to: p[4])
        return vertical / (2 * horizontal)
    }
}

/// Detects a completed blink from a stream of EAR samples: the eye must dip below
/// `closeThreshold` and then reopen above `openThreshold`. Hysteresis (two
/// thresholds) stops noise near the boundary from firing spurious blinks.
public struct BlinkDetector: Sendable {
    public var closeThreshold: Double
    public var openThreshold: Double

    private enum State { case open, closed }
    private var state: State = .open

    /// Number of full blinks seen since the detector was created or reset.
    public private(set) var blinkCount: Int = 0

    public init(closeThreshold: Double = 0.18, openThreshold: Double = 0.25) {
        self.closeThreshold = closeThreshold
        self.openThreshold = openThreshold
    }

    public mutating func reset() {
        state = .open
        blinkCount = 0
    }

    /// Feed one EAR sample. Returns true on the frame a blink *completes*
    /// (the reopening), so callers can treat it as a discrete event.
    @discardableResult
    public mutating func process(ear: Double) -> Bool {
        switch state {
        case .open:
            if ear < closeThreshold { state = .closed }
            return false
        case .closed:
            if ear > openThreshold {
                state = .open
                blinkCount += 1
                return true
            }
            return false
        }
    }
}
