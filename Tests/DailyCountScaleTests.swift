import XCTest
@testable import Pomodoro

final class DailyCountScaleTests: XCTestCase {
    func testEmptyRangeStillShowsZeroAndOne() {
        let scale = DailyCountScale(peak: 0)
        XCTAssertEqual(scale.stride, 1)
        XCTAssertEqual(scale.upperBound, 1)
        XCTAssertEqual(scale.ticks, [0, 1])
    }

    func testSinglePomodoroUsesUnitTicks() {
        let scale = DailyCountScale(peak: 1)
        XCTAssertEqual(scale.ticks, [0, 1])
    }

    func testLowCountsTickEveryPomodoro() {
        XCTAssertEqual(DailyCountScale(peak: 3).ticks, [0, 1, 2, 3])
        XCTAssertEqual(DailyCountScale(peak: 4).ticks, [0, 1, 2, 3, 4])
    }

    func testMidCountsUseEvenTicksAndRoundTheTop() {
        let five = DailyCountScale(peak: 5)
        XCTAssertEqual(five.stride, 2)
        XCTAssertEqual(five.upperBound, 6)
        XCTAssertEqual(five.ticks, [0, 2, 4, 6])

        XCTAssertEqual(DailyCountScale(peak: 8).ticks, [0, 2, 4, 6, 8])
        XCTAssertEqual(DailyCountScale(peak: 10).ticks, [0, 2, 4, 6, 8, 10])
    }

    func testHighCountsStepByFour() {
        let eleven = DailyCountScale(peak: 11)
        XCTAssertEqual(eleven.stride, 4)
        XCTAssertEqual(eleven.upperBound, 12)
        XCTAssertEqual(eleven.ticks, [0, 4, 8, 12])

        XCTAssertEqual(DailyCountScale(peak: 16).ticks, [0, 4, 8, 12, 16])
        XCTAssertEqual(DailyCountScale(peak: 20).ticks, [0, 4, 8, 12, 16, 20])
    }

    func testVeryHighCountsStepByFive() {
        let scale = DailyCountScale(peak: 21)
        XCTAssertEqual(scale.stride, 5)
        XCTAssertEqual(scale.upperBound, 25)
        XCTAssertEqual(scale.ticks, [0, 5, 10, 15, 20, 25])
    }

    func testNegativePeakIsTreatedAsEmpty() {
        XCTAssertEqual(DailyCountScale(peak: -3), DailyCountScale(peak: 0))
    }
}
