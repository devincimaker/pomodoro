import SwiftData
import XCTest
@testable import Pomodoro

/// POM-13: scrubbing remaining time updates the clock, lock screen, and
/// armed alerts without completing the block or forking alarm bookkeeping.
@MainActor
final class TimerEngineSeekTests: XCTestCase {
    private var harness: QuietLockScreenHarness!

    override func tearDown() async throws {
        harness?.tearDown()
        harness = nil
        try await super.tearDown()
    }

    func testSilentSeekUpdatesRemainingAndLockScreenWithoutArming() async throws {
        harness = try QuietLockScreenHarness.make(style: .silent)
        harness.engine.start()
        await harness.settle()

        harness.engine.seek(progress: 0.5, rearm: true)
        await harness.settle()

        XCTAssertEqual(harness.engine.remaining, 12.5 * 60, accuracy: 1.5)
        XCTAssertTrue(harness.engine.isRunning)
        XCTAssertTrue(harness.alarms.scheduledCountdowns.isEmpty)
        XCTAssertTrue(harness.alarms.activeIDs.isEmpty)

        guard case .running(let phase, let endDate, let total) = harness.spy.current else {
            return XCTFail("expected running snapshot, got \(harness.spy.current)")
        }
        XCTAssertEqual(phase, .focus)
        XCTAssertEqual(total, 25 * 60)
        XCTAssertEqual(endDate.timeIntervalSinceNow, 12.5 * 60, accuracy: 1.5)
    }

    func testLoudSeekReschedulesAlarmKitForTheNewRemaining() async throws {
        harness = try QuietLockScreenHarness.make(style: .loud, alarmAuthorization: true)
        harness.engine.start()
        await harness.settle()
        XCTAssertEqual(harness.alarms.scheduledCountdowns.count, 1)
        let originalID = harness.alarms.activeIDs.first

        harness.engine.seek(progress: 0.5, rearm: false)
        XCTAssertTrue(harness.alarms.activeIDs.isEmpty)
        XCTAssertEqual(harness.engine.remaining, 12.5 * 60, accuracy: 1.5)

        harness.engine.seek(progress: 0.5, rearm: true)
        await harness.settle()

        XCTAssertEqual(harness.alarms.scheduledCountdowns.count, 2)
        XCTAssertEqual(harness.alarms.scheduledCountdowns.last?.seconds ?? 0, 12.5 * 60, accuracy: 1.5)
        XCTAssertEqual(harness.alarms.activeIDs.count, 1)
        XCTAssertNotEqual(harness.alarms.activeIDs.first, originalID)
        XCTAssertEqual(harness.spy.current, .hidden)
    }

    func testSeekClampsToFloorAndFullDuration() async throws {
        harness = try QuietLockScreenHarness.make(style: .silent)
        harness.engine.start()
        await harness.settle()

        harness.engine.seek(toRemaining: 0)
        XCTAssertEqual(harness.engine.remaining, RingSeek.remainingFloor, accuracy: 0.2)
        XCTAssertTrue(harness.engine.isRunning)
        XCTAssertFalse(harness.engine.isAlarmPresented)
        XCTAssertEqual(sessionCount(), 0)

        harness.engine.seek(toRemaining: 10_000)
        XCTAssertEqual(harness.engine.remaining, 25 * 60, accuracy: 0.2)
    }

    func testSeekWhilePausedKeepsPausedAndResumeUsesNewRemaining() async throws {
        harness = try QuietLockScreenHarness.make(style: .silent)
        harness.engine.start()
        await harness.settle()
        harness.engine.pause()

        harness.engine.seek(toRemaining: 90)
        XCTAssertFalse(harness.engine.isRunning)
        XCTAssertFalse(harness.engine.isIdle)
        XCTAssertEqual(harness.engine.remaining, 90, accuracy: 0.2)

        guard case .paused(_, let remaining, _) = harness.spy.current else {
            return XCTFail("expected paused snapshot, got \(harness.spy.current)")
        }
        XCTAssertEqual(remaining, 90, accuracy: 0.2)

        harness.engine.start()
        await harness.settle()
        XCTAssertTrue(harness.engine.isRunning)
        XCTAssertEqual(harness.engine.remaining, 90, accuracy: 1.5)
    }

    func testLoudSeekWhilePausedDropsTheOldAlarm() async throws {
        harness = try QuietLockScreenHarness.make(style: .loud, alarmAuthorization: true)
        harness.engine.start()
        await harness.settle()
        harness.engine.pause()
        XCTAssertEqual(harness.alarms.activeIDs.count, 1)

        harness.engine.seek(toRemaining: 120)
        XCTAssertTrue(harness.alarms.activeIDs.isEmpty)
        XCTAssertEqual(harness.engine.remaining, 120, accuracy: 0.2)

        harness.engine.start()
        await harness.settle()
        XCTAssertEqual(harness.alarms.scheduledCountdowns.last?.seconds ?? 0, 120, accuracy: 1.5)
        XCTAssertEqual(harness.alarms.activeIDs.count, 1)
    }

    func testIdleSeekParksOnPausedWithoutStarting() throws {
        harness = try QuietLockScreenHarness.make(style: .silent)
        harness.engine.seek(progress: 0.2)

        XCTAssertFalse(harness.engine.isRunning)
        XCTAssertFalse(harness.engine.isIdle)
        XCTAssertEqual(harness.engine.remaining, 0.8 * 25 * 60, accuracy: 0.2)
        XCTAssertTrue(harness.alarms.scheduledCountdowns.isEmpty)
    }

    func testResetAfterSeekRestoresTheFullPhase() async throws {
        harness = try QuietLockScreenHarness.make(style: .silent)
        harness.engine.start()
        await harness.settle()
        harness.engine.seek(progress: 0.7)
        harness.engine.reset()

        XCTAssertTrue(harness.engine.isIdle)
        XCTAssertEqual(harness.engine.remaining, 25 * 60)
        XCTAssertEqual(harness.engine.phase, .focus)
        XCTAssertEqual(harness.spy.current, .hidden)
        XCTAssertEqual(sessionCount(), 0)
    }

    func testSkipAfterSeekDoesNotRecordASession() async throws {
        harness = try QuietLockScreenHarness.make(style: .silent)
        harness.engine.start()
        await harness.settle()
        harness.engine.seek(progress: 0.8)
        harness.engine.skip()

        XCTAssertEqual(harness.engine.phase, .shortBreak)
        XCTAssertEqual(sessionCount(), 0)
        XCTAssertEqual(harness.spy.current, .hidden)
    }

    func testCompletedBlockAfterSeekStillRecordsConfiguredMinutes() throws {
        // A scrubbed-short focus is still one session at the configured
        // duration — we do not rewrite stats from the remaining time.
        let suiteName = "pomodoro.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(AlertStyle.silent.rawValue, forKey: "alertStyle")
        defaults.set("running", forKey: "engine.runState")
        defaults.set(Date.now.addingTimeInterval(-1), forKey: "engine.endDate")
        defaults.set(Phase.focus.rawValue, forKey: "engine.phase")

        let settings = SettingsStore(defaults: defaults)
        let container = try ModelContainer(
            for: Schema([PomodoroSession.self]),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let engine = TimerEngine(
            settings: settings,
            modelContext: container.mainContext,
            defaults: defaults,
            alarmKit: FakeAlarmScheduler(),
            quietLockScreen: QuietLockScreenSpy()
        )
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertTrue(engine.isAlarmPresented)
        XCTAssertEqual(engine.phase, .shortBreak)
        XCTAssertEqual(engine.sessionsCompletedToday(), 1)

        let sessions = try container.mainContext.fetch(FetchDescriptor<PomodoroSession>())
        XCTAssertEqual(sessions.first?.durationMinutes, 25)
    }

    func testSeekDoesNotCompleteWhileAlarmIsPresented() throws {
        let suiteName = "pomodoro.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(AlertStyle.silent.rawValue, forKey: "alertStyle")
        defaults.set("running", forKey: "engine.runState")
        defaults.set(Date.now.addingTimeInterval(-1), forKey: "engine.endDate")
        defaults.set(Phase.focus.rawValue, forKey: "engine.phase")

        let settings = SettingsStore(defaults: defaults)
        let container = try ModelContainer(
            for: Schema([PomodoroSession.self]),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let engine = TimerEngine(
            settings: settings,
            modelContext: container.mainContext,
            defaults: defaults,
            alarmKit: FakeAlarmScheduler(),
            quietLockScreen: QuietLockScreenSpy()
        )
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertTrue(engine.isAlarmPresented)
        let phase = engine.phase
        engine.seek(progress: 0.1)
        XCTAssertEqual(engine.phase, phase)
        XCTAssertTrue(engine.isAlarmPresented)
    }

    func testUncommittedSeekThenCommitLeavesTheTimerRunning() async throws {
        harness = try QuietLockScreenHarness.make(style: .headphones)
        harness.engine.start()
        await harness.settle()

        harness.engine.seek(progress: 0.25, rearm: false)
        harness.engine.seek(progress: 0.4, rearm: false)
        harness.engine.seek(progress: 0.4, rearm: true)
        await harness.settle()

        XCTAssertTrue(harness.engine.isRunning)
        XCTAssertEqual(harness.engine.remaining, 0.6 * 25 * 60, accuracy: 1.5)
        guard case .running(let phase, let endDate, let total) = harness.spy.current else {
            return XCTFail("expected running snapshot, got \(harness.spy.current)")
        }
        XCTAssertEqual(phase, .focus)
        XCTAssertEqual(total, 25 * 60)
        XCTAssertEqual(endDate.timeIntervalSinceNow, 0.6 * 25 * 60, accuracy: 1.5)
        XCTAssertTrue(harness.alarms.scheduledCountdowns.isEmpty)
    }

    private func sessionCount() -> Int {
        harness.engine.sessionsCompletedToday()
    }
}
