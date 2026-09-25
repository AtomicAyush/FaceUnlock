import XCTest
@testable import FaceUnlockCore

final class LivenessTests: XCTestCase {

    /// Six points for an open eye: wide horizontally, tall vertically.
    private func openEye() -> [Point2D] {
        [Point2D(0, 0), Point2D(1, 1), Point2D(3, 1),
         Point2D(4, 0), Point2D(3, -1), Point2D(1, -1)]
    }

    /// Same corners, but the lids are nearly shut (small vertical distances).
    private func closedEye() -> [Point2D] {
        [Point2D(0, 0), Point2D(1, 0.1), Point2D(3, 0.1),
         Point2D(4, 0), Point2D(3, -0.1), Point2D(1, -0.1)]
    }

    func testEyeAspectRatioLargerWhenOpen() throws {
        let open = try XCTUnwrap(Liveness.eyeAspectRatio(openEye()))
        let closed = try XCTUnwrap(Liveness.eyeAspectRatio(closedEye()))
        XCTAssertGreaterThan(open, closed)
        XCTAssertGreaterThan(open, 0.3)
        XCTAssertLessThan(closed, 0.1)
    }

    func testEyeAspectRatioNilForTooFewPoints() {
        XCTAssertNil(Liveness.eyeAspectRatio([Point2D(0, 0), Point2D(1, 1)]))
    }

    func testBlinkDetectorCountsOneFullBlink() {
        var detector = BlinkDetector(closeThreshold: 0.18, openThreshold: 0.25)
        // Open, then close, then open again = one blink.
        XCTAssertFalse(detector.process(ear: 0.30))
        XCTAssertFalse(detector.process(ear: 0.10)) // closing
        XCTAssertFalse(detector.process(ear: 0.12)) // still closed
        XCTAssertTrue(detector.process(ear: 0.30))  // reopened → blink completes
        XCTAssertEqual(detector.blinkCount, 1)
    }

    func testBlinkDetectorHysteresisIgnoresNoise() {
        var detector = BlinkDetector(closeThreshold: 0.18, openThreshold: 0.25)
        // Hovering between the thresholds must not register a blink.
        for ear in [0.30, 0.22, 0.20, 0.23, 0.21, 0.30] {
            detector.process(ear: ear)
        }
        XCTAssertEqual(detector.blinkCount, 0)
    }

    func testResetClearsCount() {
        var detector = BlinkDetector()
        detector.process(ear: 0.30)
        detector.process(ear: 0.10)
        detector.process(ear: 0.30)
        XCTAssertEqual(detector.blinkCount, 1)
        detector.reset()
        XCTAssertEqual(detector.blinkCount, 0)
    }
}
