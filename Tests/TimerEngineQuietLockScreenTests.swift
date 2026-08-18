import SwiftData
import XCTest
@testable import Pomodoro

/// End-to-end regressions for POM-12: quiet styles keep a lock-screen
/// countdown and never arm a system alarm to get it.
@MainActor
final class TimerEngineQuietLockScreenTests: XCTestCase {
    private var harness: QuietLockScreenHarness!

    override func tearDown() async throws {
        harness?.tearDown()
        harness = nil
        try await super.tearDown()
    }

    func testSilentStartShowsLockScreenAndDoesNotArmAlarmKit() async throws {
        harness = try QuietLockScreenHarness.make(style: .silent)
        harness.engine.start()
        await harness.settle()

        harness.spy.current.assertRunning()
        XCTAssertTrue(harness.alarms.scheduledCountdowns.isEmpty)
        XCTAssertTrue(harness.alarms.activeIDs.isEmpty)
    }

    func testHeadphonesStartShowsLockScreenAndDoesNotArmAlarmKit() async throws {
        harness = try QuietLockScreenHarness.make(style: .headphones)
        harness.engine.start()
        await harness.settle()

        harness.spy.current.assertRunning()
        XCTAssertTrue(harness.alarms.scheduledCountdowns.isEmpty)
        XCTAssertTrue(harness.alarms.activeIDs.isEmpty)
    }

    func testLoudStartWithPermissionHidesQuietActivityAndArmsAlarm() async throws {
        harness = try QuietLockScreenHarness.make(style: .loud, alarmAuthorization: true)
        harness.engine.start()
        await harness.settle()

        XCTAssertEqual(harness.spy.current, .hidden)
        XCTAssertEqual(harness.alarms.scheduledCountdowns.count, 1)
        XCTAssertEqual(harness.alarms.activeIDs.count, 1)
    }

    func testLoudWithoutPermissionFallsBackToQuietLockScreen() async throws {
        harness = try QuietLockScreenHarness.make(style: .loud, alarmAuthorization: false)
        harness.engine.start()
        await harness.settle()

        harness.spy.current.assertRunning()
        XCTAssertTrue(harness.alarms.scheduledCountdowns.isEmpty)
        XCTAssertTrue(harness.alarms.activeIDs.isEmpty)
    }

    func testSilentPauseAndResumeUpdateTheLockScreen() async throws {
        harness = try QuietLockScreenHarness.make(style: .silent)
        harness.engine.start()
        await harness.settle()
        harness.engine.pause()

        guard case .paused(let phase, let remaining, let total) = harness.spy.current else {
            return XCTFail("expected paused snapshot, got \(harness.spy.current)")
        }
        XCTAssertEqual(phase, .focus)
        XCTAssertEqual(total, 25 * 60)
        XCTAssertEqual(remaining, 25 * 60, accuracy: 1.5)

        harness.engine.start()
        await harness.settle()
        harness.spy.current.assertRunning()
    }

    func testSilentResetTearsDownTheLockScreen() async throws {
        harness = try QuietLockScreenHarness.make(style: .silent)
        harness.engine.start()
        await harness.settle()
        harness.engine.reset()

        XCTAssertEqual(harness.spy.current, .hidden)
        XCTAssertTrue(harness.alarms.activeIDs.isEmpty)
    }

    func testSilentSkipTearsDownTheLockScreen() async throws {
        harness = try QuietLockScreenHarness.make(style: .silent)
        harness.engine.start()
        await harness.settle()
        harness.engine.skip()

        XCTAssertEqual(harness.spy.current, .hidden)
        XCTAssertTrue(harness.alarms.activeIDs.isEmpty)
        XCTAssertEqual(harness.engine.phase, .shortBreak)
    }

    func testSwitchingLoudToSilentReplacesAlarmWithQuietDisplay() async throws {
        harness = try QuietLockScreenHarness.make(style: .loud, alarmAuthorization: true)
        harness.engine.start()
        await harness.settle()
        XCTAssertEqual(harness.alarms.activeIDs.count, 1)

        harness.settings.alertStyle = .silent
        harness.engine.handleAlertStyleDidChange()
        await harness.settle()

        harness.spy.current.assertRunning()
        XCTAssertTrue(harness.alarms.activeIDs.isEmpty)
    }

    func testSwitchingSilentToLoudReplacesDisplayWithAlarm() async throws {
        harness = try QuietLockScreenHarness.make(style: .silent, alarmAuthorization: true)
        harness.engine.start()
        await harness.settle()
        harness.spy.current.assertRunning()

        harness.settings.alertStyle = .loud
        harness.engine.handleAlertStyleDidChange()
        await harness.settle()

        XCTAssertEqual(harness.spy.current, .hidden)
        XCTAssertEqual(harness.alarms.activeIDs.count, 1)
    }

    func testSwitchingHeadphonesToSilentKeepsTheDisplayAndNeverArms() async throws {
        harness = try QuietLockScreenHarness.make(style: .headphones)
        harness.engine.start()
        await harness.settle()

        harness.settings.alertStyle = .silent
        harness.engine.handleAlertStyleDidChange()
        await harness.settle()

        harness.spy.current.assertRunning()
        XCTAssertTrue(harness.alarms.scheduledCountdowns.isEmpty)
        XCTAssertTrue(harness.alarms.activeIDs.isEmpty)
    }

    func testRestoredQuietRunShowsTheLockScreen() throws {
        let suiteName = "pomodoro.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(AlertStyle.silent.rawValue, forKey: "alertStyle")
        defaults.set("running", forKey: "engine.runState")
        defaults.set(Date.now.addingTimeInterval(12 * 60), forKey: "engine.endDate")
        defaults.set(Phase.focus.rawValue, forKey: "engine.phase")

        let settings = SettingsStore(defaults: defaults)
        let container = try ModelContainer(
            for: Schema([PomodoroSession.self]),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let spy = QuietLockScreenSpy()
        let alarms = FakeAlarmScheduler()
        _ = TimerEngine(
            settings: settings,
            modelContext: container.mainContext,
            defaults: defaults,
            alarmKit: alarms,
            quietLockScreen: spy
        )
        defer { defaults.removePersistentDomain(forName: suiteName) }

        guard case .running(let phase, let endDate, let total) = spy.current else {
            return XCTFail("expected restored running snapshot, got \(spy.current)")
        }
        XCTAssertEqual(phase, .focus)
        XCTAssertEqual(total, 25 * 60)
        XCTAssertEqual(endDate.timeIntervalSinceNow, 12 * 60, accuracy: 1.5)
        XCTAssertTrue(alarms.scheduledCountdowns.isEmpty)
    }

    func testPastQuietDeadlineCompletesAndHidesTheLockScreen() throws {
        let suiteName = "pomodoro.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(AlertStyle.silent.rawValue, forKey: "alertStyle")
        defaults.set("running", forKey: "engine.runState")
        defaults.set(Date.now.addingTimeInterval(-2), forKey: "engine.endDate")
        defaults.set(Phase.focus.rawValue, forKey: "engine.phase")

        let settings = SettingsStore(defaults: defaults)
        let container = try ModelContainer(
            for: Schema([PomodoroSession.self]),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let spy = QuietLockScreenSpy()
        let engine = TimerEngine(
            settings: settings,
            modelContext: container.mainContext,
            defaults: defaults,
            alarmKit: FakeAlarmScheduler(),
            quietLockScreen: spy
        )
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertTrue(engine.isAlarmPresented)
        XCTAssertEqual(spy.current, .hidden)
        XCTAssertEqual(engine.phase, .shortBreak)
    }
}
