import XCTest
@testable import Pomodoro

final class RingSeekTests: XCTestCase {
    private let size = CGSize(width: 290, height: 290)

    func testTwelveOClockIsZeroProgress() {
        let progress = RingSeek.progress(at: CGPoint(x: 145, y: 8), in: size)
        XCTAssertEqual(progress ?? -1, 0, accuracy: 0.02)
    }

    func testThreeOClockIsQuarterProgress() {
        let progress = RingSeek.progress(at: CGPoint(x: 282, y: 145), in: size)
        XCTAssertEqual(progress ?? -1, 0.25, accuracy: 0.02)
    }

    func testSixOClockIsHalfProgress() {
        let progress = RingSeek.progress(at: CGPoint(x: 145, y: 282), in: size)
        XCTAssertEqual(progress ?? -1, 0.50, accuracy: 0.02)
    }

    func testNineOClockIsThreeQuarterProgress() {
        let progress = RingSeek.progress(at: CGPoint(x: 8, y: 145), in: size)
        XCTAssertEqual(progress ?? -1, 0.75, accuracy: 0.02)
    }

    func testCenterIsDeadZone() {
        XCTAssertNil(RingSeek.progress(at: CGPoint(x: 145, y: 145), in: size))
    }

    func testOutsideTheRingIsDeadZone() {
        XCTAssertNil(RingSeek.progress(at: CGPoint(x: 2, y: 2), in: size))
    }

    func testHalfProgressIsHalfRemaining() {
        XCTAssertEqual(RingSeek.remaining(progress: 0.5, total: 25 * 60), 12.5 * 60, accuracy: 0.01)
    }

    func testFullProgressClampsToRemainingFloor() {
        XCTAssertEqual(RingSeek.remaining(progress: 1, total: 25 * 60), RingSeek.remainingFloor)
    }

    func testZeroProgressIsFullDuration() {
        XCTAssertEqual(RingSeek.remaining(progress: 0, total: 25 * 60), 25 * 60)
    }

    func testRemainingClampsPastTheStart() {
        XCTAssertEqual(RingSeek.clampedRemaining(10_000, total: 5 * 60), 5 * 60)
    }

    func testRemainingClampsPastTheEnd() {
        XCTAssertEqual(RingSeek.clampedRemaining(0, total: 25 * 60), RingSeek.remainingFloor)
        XCTAssertEqual(RingSeek.clampedRemaining(-20, total: 25 * 60), RingSeek.remainingFloor)
    }

    func testCrossingNoonClockwiseStaysAtEnd() {
        XCTAssertEqual(RingSeek.clampedProgress(0.05, previous: 0.97), 1, accuracy: 0.001)
    }

    func testCrossingNoonCounterClockwiseStaysAtStart() {
        XCTAssertEqual(RingSeek.clampedProgress(0.97, previous: 0.04), 0, accuracy: 0.001)
    }

    func testNormalClockwiseDragDoesNotClamp() {
        XCTAssertEqual(RingSeek.clampedProgress(0.40, previous: 0.35), 0.40, accuracy: 0.001)
    }
}
