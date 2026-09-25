import XCTest
@testable import FaceUnlockCore

final class SimilarityTransformTests: XCTestCase {

    func testIdentityRecoversPoints() throws {
        let pts = [Point2D(0, 0), Point2D(1, 0), Point2D(0, 1), Point2D(1, 1)]
        let t = SimilarityTransform.fit(source: pts, destination: pts)
        let s = try XCTUnwrap(t)
        XCTAssertEqual(s.a, 1, accuracy: 1e-9)
        XCTAssertEqual(s.b, 0, accuracy: 1e-9)
        XCTAssertEqual(s.tx, 0, accuracy: 1e-9)
        XCTAssertEqual(s.ty, 0, accuracy: 1e-9)
    }

    func testPureTranslation() throws {
        let src = [Point2D(0, 0), Point2D(2, 0), Point2D(0, 2)]
        let dst = src.map { Point2D($0.x + 5, $0.y - 3) }
        let s = try XCTUnwrap(SimilarityTransform.fit(source: src, destination: dst))
        XCTAssertEqual(s.scale, 1, accuracy: 1e-9)
        XCTAssertEqual(s.tx, 5, accuracy: 1e-9)
        XCTAssertEqual(s.ty, -3, accuracy: 1e-9)
    }

    func testUniformScale() throws {
        let src = [Point2D(1, 1), Point2D(3, 1), Point2D(1, 4)]
        let dst = src.map { Point2D($0.x * 2, $0.y * 2) }
        let s = try XCTUnwrap(SimilarityTransform.fit(source: src, destination: dst))
        XCTAssertEqual(s.scale, 2, accuracy: 1e-9)
        for (a, b) in zip(src, dst) {
            let m = s.apply(to: a)
            XCTAssertEqual(m.x, b.x, accuracy: 1e-7)
            XCTAssertEqual(m.y, b.y, accuracy: 1e-7)
        }
    }

    func testNinetyDegreeRotation() throws {
        // Rotate +90°: (x, y) -> (-y, x).
        let src = [Point2D(1, 0), Point2D(0, 1), Point2D(2, 3), Point2D(-1, 2)]
        let dst = src.map { Point2D(-$0.y, $0.x) }
        let s = try XCTUnwrap(SimilarityTransform.fit(source: src, destination: dst))
        XCTAssertEqual(s.scale, 1, accuracy: 1e-7)
        XCTAssertEqual(s.rotation, .pi / 2, accuracy: 1e-7)
        for (a, b) in zip(src, dst) {
            let m = s.apply(to: a)
            XCTAssertEqual(m.x, b.x, accuracy: 1e-7)
            XCTAssertEqual(m.y, b.y, accuracy: 1e-7)
        }
    }

    func testDegenerateInputReturnsNil() {
        let src = [Point2D(1, 1), Point2D(1, 1), Point2D(1, 1)]
        let dst = [Point2D(0, 0), Point2D(1, 0), Point2D(0, 1)]
        XCTAssertNil(SimilarityTransform.fit(source: src, destination: dst))
    }

    func testMismatchedCountsReturnNil() {
        XCTAssertNil(SimilarityTransform.fit(source: [Point2D(0, 0)],
                                             destination: [Point2D(0, 0), Point2D(1, 1)]))
    }
}
