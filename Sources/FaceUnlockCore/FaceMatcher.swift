import Foundation

/// Compares a probe face embedding against an enrolled gallery using cosine
/// similarity. Pure and deterministic — the whole matching decision is testable
/// without a camera or a model.
public struct FaceMatcher: Sendable {
    /// Minimum cosine similarity to count as the same person. The default suits
    /// SFace's 128-D embeddings; recalibrate if the model changes.
    public var threshold: Double

    public init(threshold: Double = RecognitionConfig.default.cosineThreshold) {
        self.threshold = threshold
    }

    /// L2-normalise a vector. A zero vector is returned unchanged.
    public static func normalized(_ v: [Float]) -> [Float] {
        var sum: Double = 0
        for x in v { sum += Double(x) * Double(x) }
        let norm = sum.squareRoot()
        guard norm > 1e-12 else { return v }
        return v.map { Float(Double($0) / norm) }
    }

    /// Cosine similarity of two equal-length vectors, in [-1, 1].
    /// Returns 0 for mismatched or empty vectors.
    public static func cosine(_ a: [Float], _ b: [Float]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Double = 0, na: Double = 0, nb: Double = 0
        for i in a.indices {
            let x = Double(a[i]); let y = Double(b[i])
            dot += x * y; na += x * x; nb += y * y
        }
        let denom = (na.squareRoot()) * (nb.squareRoot())
        guard denom > 1e-12 else { return 0 }
        return dot / denom
    }

    public struct Match: Sendable, Equatable {
        public let index: Int
        public let score: Double
    }

    /// Best-scoring gallery entry for a probe, or nil if the gallery is empty.
    /// Uses max-of-cosine across the enrolled samples (a gallery, not an average),
    /// which tolerates pose and lighting variation better than a single mean.
    public func bestMatch(probe: [Float], gallery: [[Float]]) -> Match? {
        var best: Match?
        for (i, g) in gallery.enumerated() {
            let s = Self.cosine(probe, g)
            if best == nil || s > best!.score {
                best = Match(index: i, score: s)
            }
        }
        return best
    }

    /// Whether the probe matches anyone in the gallery at or above the threshold.
    public func isMatch(probe: [Float], gallery: [[Float]]) -> Bool {
        guard let m = bestMatch(probe: probe, gallery: gallery) else { return false }
        return m.score >= threshold
    }
}
