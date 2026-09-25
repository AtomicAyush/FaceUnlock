import Foundation
import Vision
import CoreVideo
import FaceUnlockCore

/// One detected face, with everything the downstream pipeline needs, expressed in
/// image-pixel coordinates with a top-left origin (the CVPixelBuffer convention).
public struct DetectedFace: Sendable {
    /// Face bounding box in pixels, top-left origin.
    public var boundingBox: CGRect
    /// Five alignment landmarks in pixels: left eye, right eye, nose tip,
    /// left mouth corner, right mouth corner.
    public var fivePoints: [Point2D]
    /// Eye-aspect-ratio landmarks (6 per eye) in pixels, for liveness.
    public var leftEyePoints: [Point2D]
    public var rightEyePoints: [Point2D]
    /// Vision's capture-quality score, 0…1, if available.
    public var quality: Float?

    /// Area of the bounding box — used to pick the largest (nearest) face.
    public var area: CGFloat { boundingBox.width * boundingBox.height }
}

/// Wraps Vision's landmark and quality requests and converts their normalised,
/// bottom-left-origin output into pixel points the aligner can use.
///
/// Note: the five-point derivation from Vision's landmark regions is standard but
/// benefits from on-device calibration against real faces; the geometry is
/// documented inline so it can be checked against captured frames.
public final class FaceDetector {

    public init() {}

    public func detect(in pixelBuffer: CVPixelBuffer) -> [DetectedFace] {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width > 0, height > 0 else { return [] }

        let landmarks = VNDetectFaceLandmarksRequest()
        let quality = VNDetectFaceCaptureQualityRequest()

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        do {
            try handler.perform([landmarks, quality])
        } catch {
            return []
        }

        // Pair each landmark observation with a quality score by matching the
        // observation UUID where possible; fall back to positional order.
        let qualityByID: [UUID: Float] = Dictionary(
            uniqueKeysWithValues: (quality.results ?? []).compactMap { obs in
                obs.faceCaptureQuality.map { (obs.uuid, $0) }
            }
        )

        var faces: [DetectedFace] = []
        for obs in landmarks.results ?? [] {
            guard let lm = obs.landmarks else { continue }
            let box = pixelRect(obs.boundingBox, width: width, height: height)

            func pixels(_ region: VNFaceLandmarkRegion2D?) -> [Point2D] {
                guard let region else { return [] }
                return region.normalizedPoints.map { np in
                    normalizedFacePointToPixel(np, box: obs.boundingBox, width: width, height: height)
                }
            }

            let leftEye = pixels(lm.leftEye)
            let rightEye = pixels(lm.rightEye)
            let nose = pixels(lm.nose)
            let outerLips = pixels(lm.outerLips)

            guard let five = fivePoints(leftEye: leftEye, rightEye: rightEye,
                                        nose: nose, outerLips: outerLips)
            else { continue }

            faces.append(DetectedFace(
                boundingBox: box,
                fivePoints: five,
                leftEyePoints: leftEye,
                rightEyePoints: rightEye,
                quality: qualityByID[obs.uuid]
            ))
        }
        return faces
    }

    // MARK: - Coordinate conversion

    /// Convert a Vision normalized rect (0…1, bottom-left origin) to pixels,
    /// top-left origin.
    private func pixelRect(_ r: CGRect, width: Int, height: Int) -> CGRect {
        let w = CGFloat(width), h = CGFloat(height)
        let x = r.origin.x * w
        let yTop = (1 - r.origin.y - r.height) * h
        return CGRect(x: x, y: yTop, width: r.width * w, height: r.height * h)
    }

    /// Convert a landmark point (normalised *within the face box*, bottom-left
    /// origin) to absolute pixels with a top-left origin.
    private func normalizedFacePointToPixel(_ p: CGPoint, box: CGRect, width: Int, height: Int) -> Point2D {
        let w = Double(width), h = Double(height)
        let absX = (Double(box.origin.x) + Double(p.x) * Double(box.width)) * w
        let absYBottom = (Double(box.origin.y) + Double(p.y) * Double(box.height)) * h
        let absYTop = h - absYBottom
        return Point2D(absX, absYTop)
    }

    /// Derive the five alignment points from Vision's landmark regions.
    private func fivePoints(leftEye: [Point2D], rightEye: [Point2D],
                            nose: [Point2D], outerLips: [Point2D]) -> [Point2D]? {
        guard let leftEyeC = centroid(of: leftEye),
              let rightEyeC = centroid(of: rightEye),
              !nose.isEmpty, !outerLips.isEmpty
        else { return nil }

        // Nose tip: the lowest nose point in image space (largest y, top-left origin).
        let noseTip = nose.max(by: { $0.y < $1.y }) ?? (centroid(of: nose) ?? leftEyeC)

        // Mouth corners: extreme x of the outer-lip contour.
        let leftMouth = outerLips.min(by: { $0.x < $1.x })!
        let rightMouth = outerLips.max(by: { $0.x < $1.x })!

        return [leftEyeC, rightEyeC, noseTip, leftMouth, rightMouth]
    }
}
