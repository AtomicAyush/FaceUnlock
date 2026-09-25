import XCTest
@testable import FaceUnlockCore

final class FaceMatcherTests: XCTestCase {

    func testCosineOfIdenticalIsOne() {
        let v: [Float] = [1, 2, 3, 4]
        XCTAssertEqual(FaceMatcher.cosine(v, v), 1, accuracy: 1e-9)
    }

    func testCosineOfOrthogonalIsZero() {
        XCTAssertEqual(FaceMatcher.cosine([1, 0], [0, 1]), 0, accuracy: 1e-9)
    }

    func testCosineOfOppositeIsMinusOne() {
        XCTAssertEqual(FaceMatcher.cosine([1, 1], [-1, -1]), -1, accuracy: 1e-9)
    }

    func testCosineMismatchedLengthIsZero() {
        XCTAssertEqual(FaceMatcher.cosine([1, 2, 3], [1, 2]), 0)
    }

    func testNormalizedHasUnitLength() {
        let n = FaceMatcher.normalized([3, 4]) // length 5
        XCTAssertEqual(n[0], 0.6, accuracy: 1e-6)
        XCTAssertEqual(n[1], 0.8, accuracy: 1e-6)
    }

    func testBestMatchPicksHighestScore() {
        let probe: [Float] = [1, 0, 0]
        let gallery: [[Float]] = [[0, 1, 0], [0.9, 0.1, 0], [1, 0, 0]]
        let matcher = FaceMatcher(threshold: 0.5)
        let best = matcher.bestMatch(probe: probe, gallery: gallery)
        XCTAssertEqual(best?.index, 2)
        XCTAssertEqual(best?.score ?? 0, 1, accuracy: 1e-9)
    }

    func testIsMatchRespectsThreshold() {
        let probe: [Float] = [1, 0]
        let near: [[Float]] = [[0.95, 0.31]]   // cosine ≈ 0.95
        let far: [[Float]] = [[0.1, 1.0]]      // cosine ≈ 0.1
        XCTAssertTrue(FaceMatcher(threshold: 0.36).isMatch(probe: probe, gallery: near))
        XCTAssertFalse(FaceMatcher(threshold: 0.36).isMatch(probe: probe, gallery: far))
    }

    func testEmptyGalleryDoesNotMatch() {
        XCTAssertFalse(FaceMatcher().isMatch(probe: [1, 2, 3], gallery: []))
        XCTAssertNil(FaceMatcher().bestMatch(probe: [1, 2, 3], gallery: []))
    }
}
