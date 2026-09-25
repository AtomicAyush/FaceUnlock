import Foundation
import CoreImage
import CoreVideo
import FaceUnlockCore

/// Warps a detected face into the model's canonical 112×112 crop using the
/// similarity transform fitted from the five landmarks.
///
/// The fit is done in Core Image's native bottom-left coordinate space (both the
/// detected points and the template are converted to it first), so no manual image
/// flip is needed. The exact vertical orientation of the produced crop should be
/// eyeballed once against a real captured face when the embedding model is added —
/// `debugCGImage(from:)` exists for exactly that check.
public final class FaceAligner {

    private let context: CIContext
    private let outputSize: Int
    private var pixelBufferPool: CVPixelBufferPool?

    public init(outputSize: Int = AlignmentTemplate.outputSize) {
        self.outputSize = outputSize
        // Software-agnostic context; Metal-backed when available.
        self.context = CIContext(options: [.useSoftwareRenderer: false])
    }

    /// Produce a 112×112 BGRA pixel buffer aligned to the template, or nil if the
    /// landmarks are degenerate.
    public func alignedPixelBuffer(from face: DetectedFace, in source: CVPixelBuffer) -> CVPixelBuffer? {
        guard let transform = transform(for: face, imageHeight: CVPixelBufferGetHeight(source)) else {
            return nil
        }
        let ci = CIImage(cvPixelBuffer: source).transformed(by: transform)
        guard let out = makePixelBuffer() else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: outputSize, height: outputSize)
        context.render(ci, to: out, bounds: bounds, colorSpace: CGColorSpaceCreateDeviceRGB())
        return out
    }

    /// A CGImage of the aligned crop, for visual verification during model bring-up.
    public func debugCGImage(from face: DetectedFace, in source: CVPixelBuffer) -> CGImage? {
        guard let transform = transform(for: face, imageHeight: CVPixelBufferGetHeight(source)) else {
            return nil
        }
        let ci = CIImage(cvPixelBuffer: source).transformed(by: transform)
        let bounds = CGRect(x: 0, y: 0, width: outputSize, height: outputSize)
        return context.createCGImage(ci, from: bounds)
    }

    // MARK: - Internals

    private func transform(for face: DetectedFace, imageHeight: Int) -> CGAffineTransform? {
        let h = Double(imageHeight)
        // Detected points are top-left origin; flip to bottom-left for Core Image.
        let src = face.fivePoints.map { Point2D($0.x, h - $0.y) }
        let dstH = Double(outputSize)
        let dst = AlignmentTemplate.fivePoints.map { Point2D($0.x, dstH - $0.y) }

        guard let s = SimilarityTransform.fit(source: src, destination: dst) else { return nil }
        // x' = a·x − b·y + tx ; y' = b·x + a·y + ty  →  CGAffineTransform fields.
        return CGAffineTransform(a: s.a, b: s.b, c: -s.b, d: s.a, tx: s.tx, ty: s.ty)
    }

    private func makePixelBuffer() -> CVPixelBuffer? {
        if pixelBufferPool == nil {
            let attrs: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey as String: outputSize,
                kCVPixelBufferHeightKey as String: outputSize,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            ]
            var pool: CVPixelBufferPool?
            CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attrs as CFDictionary, &pool)
            pixelBufferPool = pool
        }
        guard let pool = pixelBufferPool else { return nil }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer)
        return buffer
    }
}
