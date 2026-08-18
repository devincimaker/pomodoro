import XCTest
@testable import Pomodoro

final class CycleGroupPolicyTests: XCTestCase {
    func testCannotStartNewCycleOnAFreshFocusBlock() {
        XCTAssertFalse(
            CycleGroupPolicy.canStartNewCycle(
                completedInCycle: 0,
                phase: .focus,
                isAlarmPresented: false
            )
        )
    }

    func testCanStartNewCycleAfterFocusBlocksOrOnABreak() {
        XCTAssertTrue(
            CycleGroupPolicy.canStartNewCycle(
                completedInCycle: 2,
                phase: .focus,
                isAlarmPresented: false
            )
        )
        XCTAssertTrue(
            CycleGroupPolicy.canStartNewCycle(
                completedInCycle: 0,
                phase: .shortBreak,
                isAlarmPresented: false
            )
        )
    }

    func testCannotStartNewCycleWhileTheAlarmIsUp() {
        XCTAssertFalse(
            CycleGroupPolicy.canStartNewCycle(
                completedInCycle: 2,
                phase: .shortBreak,
                isAlarmPresented: true
            )
        )
    }

    func testDoesNotExpireWithoutALastActivity() {
        XCTAssertFalse(
            CycleGroupPolicy.shouldStartNewGroup(
                lastActivityAt: nil,
                now: Date(timeIntervalSince1970: 10_000),
                isActivelyTiming: false
            )
        )
    }

    func testDoesNotExpireBeforeFourHours() {
        let now = Date(timeIntervalSince1970: 20_000)
        XCTAssertFalse(
            CycleGroupPolicy.shouldStartNewGroup(
                lastActivityAt: now.addingTimeInterval(-CycleGroupPolicy.inactivityLimit + 1),
                now: now,
                isActivelyTiming: false
            )
        )
    }

    func testExpiresAtExactlyFourHours() {
        let now = Date(timeIntervalSince1970: 20_000)
        XCTAssertTrue(
            CycleGroupPolicy.shouldStartNewGroup(
                lastActivityAt: now.addingTimeInterval(-CycleGroupPolicy.inactivityLimit),
                now: now,
                isActivelyTiming: false
            )
        )
    }

    func testDoesNotExpireAStillCountingTimer() {
        let now = Date(timeIntervalSince1970: 20_000)
        XCTAssertFalse(
            CycleGroupPolicy.shouldStartNewGroup(
                lastActivityAt: now.addingTimeInterval(-CycleGroupPolicy.inactivityLimit * 2),
                now: now,
                isActivelyTiming: true
            )
        )
    }
}
