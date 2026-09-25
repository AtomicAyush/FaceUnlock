import Foundation

/// The canonical five-point face template used by ArcFace / SFace-style models,
/// given in pixels for a 112×112 aligned crop. Order: left eye, right eye,
/// nose tip, left mouth corner, right mouth corner — all from the *subject's*
/// perspective is not assumed here; callers must supply detected points in this
/// same order. Coordinates are the widely-used insightface reference values.
public enum AlignmentTemplate {
    public static let outputSize = 112

    public static let fivePoints: [Point2D] = [
        Point2D(38.2946, 51.6963), // left eye
        Point2D(73.5318, 51.5014), // right eye
        Point2D(56.0252, 71.7366), // nose tip
        Point2D(41.5493, 92.3655), // left mouth corner
        Point2D(70.7299, 92.2041), // right mouth corner
    ]
}
