import XCTest
@testable import Pomodoro

/// Pure-policy regressions for the app-owned lock-screen activity.
///
/// If these fail, Silent / Headphones will either lose the lock-screen
/// countdown again or stack it on top of AlarmKit's ringing activity.
final class QuietLockScreenPolicyTests: XCTestCase {
    private let end = Date(timeIntervalSince1970: 1_700_000_000)
    private let total: TimeInterval = 25 * 60

    func testIdleIsHiddenInEveryStyle() {
        for usesAlarmKitDisplay in [false, true] {
            let snapshot = QuietLockScreenPolicy.snapshot(
                usesAlarmKitDisplay: usesAlarmKitDisplay,
                timer: .idle,
                phase: .focus,
                isAlarmPresented: false,
                totalDuration: total
            )
            XCTAssertEqual(snapshot, .hidden)
        }
    }

    func testQuietRunningShowsCountdown() {
        let snapshot = QuietLockScreenPolicy.snapshot(
            usesAlarmKitDisplay: false,
            timer: .running(endDate: end),
            phase: .focus,
            isAlarmPresented: false,
            totalDuration: total
        )
        XCTAssertEqual(snapshot, .running(phase: .focus, endDate: end, totalDuration: total))
    }

    func testQuietPausedShowsFrozenRemaining() {
        let snapshot = QuietLockScreenPolicy.snapshot(
            usesAlarmKitDisplay: false,
            timer: .paused(remaining: 90),
            phase: .shortBreak,
            isAlarmPresented: false,
            totalDuration: 5 * 60
        )
        XCTAssertEqual(
            snapshot,
            .paused(phase: .shortBreak, remaining: 90, totalDuration: 5 * 60)
        )
    }

    func testAlarmKitDisplayHidesQuietActivityWhileRunning() {
        let snapshot = QuietLockScreenPolicy.snapshot(
            usesAlarmKitDisplay: true,
            timer: .running(endDate: end),
            phase: .focus,
            isAlarmPresented: false,
            totalDuration: total
        )
        XCTAssertEqual(snapshot, .hidden)
    }

    func testAlarmKitDisplayHidesQuietActivityWhilePaused() {
        let snapshot = QuietLockScreenPolicy.snapshot(
            usesAlarmKitDisplay: true,
            timer: .paused(remaining: 30),
            phase: .focus,
            isAlarmPresented: false,
            totalDuration: total
        )
        XCTAssertEqual(snapshot, .hidden)
    }

    func testCompletionHidesQuietActivityEvenWithoutAlarmKit() {
        let snapshot = QuietLockScreenPolicy.snapshot(
            usesAlarmKitDisplay: false,
            timer: .idle,
            phase: .shortBreak,
            isAlarmPresented: true,
            totalDuration: total
        )
        XCTAssertEqual(snapshot, .hidden)
    }

    func testCompletionHidesAStillRunningTimer() {
        // Time's up can fire while state has not yet been cleared.
        let snapshot = QuietLockScreenPolicy.snapshot(
            usesAlarmKitDisplay: false,
            timer: .running(endDate: end),
            phase: .focus,
            isAlarmPresented: true,
            totalDuration: total
        )
        XCTAssertEqual(snapshot, .hidden)
    }

    func testLongBreakUsesItsOwnPhase() {
        let snapshot = QuietLockScreenPolicy.snapshot(
            usesAlarmKitDisplay: false,
            timer: .running(endDate: end),
            phase: .longBreak,
            isAlarmPresented: false,
            totalDuration: 15 * 60
        )
        XCTAssertEqual(
            snapshot,
            .running(phase: .longBreak, endDate: end, totalDuration: 15 * 60)
        )
    }
}
