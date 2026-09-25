import Foundation

/// A point in image-pixel space, top-left origin. Doubles for numerical headroom
/// in the alignment least-squares; the pixel counts themselves are small.
public struct Point2D: Equatable, Sendable, Codable {
    public var x: Double
    public var y: Double

    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    public static func - (lhs: Point2D, rhs: Point2D) -> Point2D {
        Point2D(lhs.x - rhs.x, lhs.y - rhs.y)
    }

    public static func + (lhs: Point2D, rhs: Point2D) -> Point2D {
        Point2D(lhs.x + rhs.x, lhs.y + rhs.y)
    }

    /// Euclidean length from the origin.
    public var length: Double { (x * x + y * y).squareRoot() }

    /// Euclidean distance to another point.
    public func distance(to other: Point2D) -> Double {
        (self - other).length
    }
}

/// The centroid of a set of points, or nil for an empty set.
public func centroid(of points: [Point2D]) -> Point2D? {
    guard !points.isEmpty else { return nil }
    var sx = 0.0, sy = 0.0
    for p in points { sx += p.x; sy += p.y }
    let n = Double(points.count)
    return Point2D(sx / n, sy / n)
}
