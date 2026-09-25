import Foundation

/// A 2-D similarity transform: uniform scale, rotation, and translation, but no
/// reflection or shear. This is exactly the family ArcFace-style face alignment
/// uses to map a detected face's five landmarks onto a fixed 112×112 template
/// (the same transform scikit-image calls `SimilarityTransform`).
///
/// The mapping is
///     x' = a·x − b·y + tx
///     y' = b·x + a·y + ty
/// where `(a, b)` encode scale·(cos θ, sin θ). Fitting `a, b, tx, ty` to point
/// correspondences is *linear*, so we solve it in closed form — no SVD needed.
public struct SimilarityTransform: Equatable, Sendable {
    public var a: Double
    public var b: Double
    public var tx: Double
    public var ty: Double

    public init(a: Double, b: Double, tx: Double, ty: Double) {
        self.a = a
        self.b = b
        self.tx = tx
        self.ty = ty
    }

    public static let identity = SimilarityTransform(a: 1, b: 0, tx: 0, ty: 0)

    /// The uniform scale factor this transform applies.
    public var scale: Double { (a * a + b * b).squareRoot() }

    /// The rotation angle in radians.
    public var rotation: Double { atan2(b, a) }

    /// Map a point through the transform.
    public func apply(to p: Point2D) -> Point2D {
        Point2D(a * p.x - b * p.y + tx, b * p.x + a * p.y + ty)
    }

    /// Least-squares similarity transform mapping `source` onto `destination`.
    ///
    /// Requires at least two correspondences and equal counts. Returns nil if the
    /// system is degenerate (e.g. all source points coincident), which alignment
    /// code should treat as "could not align this face."
    public static func fit(source: [Point2D], destination: [Point2D]) -> SimilarityTransform? {
        guard source.count == destination.count, source.count >= 2 else { return nil }

        // Normal equations AᵀA·p = Aᵀd for p = [a, b, tx, ty].
        // Each correspondence contributes two rows:
        //   x': [ x, -y, 1, 0 ] · p = x'
        //   y': [ y,  x, 0, 1 ] · p = y'
        var ata = [[Double]](repeating: [Double](repeating: 0, count: 4), count: 4)
        var atd = [Double](repeating: 0, count: 4)

        func accumulate(row: [Double], target: Double) {
            for i in 0..<4 {
                atd[i] += row[i] * target
                for j in 0..<4 {
                    ata[i][j] += row[i] * row[j]
                }
            }
        }

        for (s, d) in zip(source, destination) {
            accumulate(row: [s.x, -s.y, 1, 0], target: d.x)
            accumulate(row: [s.y,  s.x, 0, 1], target: d.y)
        }

        guard let p = solve4x4(ata, atd) else { return nil }
        return SimilarityTransform(a: p[0], b: p[1], tx: p[2], ty: p[3])
    }
}

/// Solve a 4×4 linear system by Gaussian elimination with partial pivoting.
/// Returns nil if the matrix is (numerically) singular.
func solve4x4(_ matrix: [[Double]], _ rhs: [Double]) -> [Double]? {
    let n = 4
    var m = matrix
    var v = rhs

    for col in 0..<n {
        // Partial pivot: find the row with the largest magnitude in this column.
        var pivot = col
        var best = abs(m[col][col])
        for r in (col + 1)..<n where abs(m[r][col]) > best {
            best = abs(m[r][col])
            pivot = r
        }
        guard best > 1e-12 else { return nil }
        if pivot != col {
            m.swapAt(col, pivot)
            v.swapAt(col, pivot)
        }

        // Eliminate below the pivot.
        for r in (col + 1)..<n {
            let factor = m[r][col] / m[col][col]
            guard factor != 0 else { continue }
            for c in col..<n { m[r][c] -= factor * m[col][c] }
            v[r] -= factor * v[col]
        }
    }

    // Back-substitution.
    var x = [Double](repeating: 0, count: n)
    for row in stride(from: n - 1, through: 0, by: -1) {
        var sum = v[row]
        for c in (row + 1)..<n { sum -= m[row][c] * x[c] }
        x[row] = sum / m[row][row]
    }
    return x
}
