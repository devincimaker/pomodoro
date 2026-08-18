import SwiftData
import XCTest
@testable import Pomodoro

/// POM-9: a long gap (or a manual reset) starts a new short-break /
/// long-break group without deleting recorded focus sessions.
@MainActor
final class TimerEngineCycleGroupTests: XCTestCase {
    private var harness: QuietLockScreenHarness!

    override func tearDown() async throws {
        harness?.tearDown()
        harness = nil
        try await super.tearDown()
    }

    func testManualNewCycleResetsCadenceAndKeepsSessions() async throws {
        harness = try QuietLockScreenHarness.make(style: .silent)
        insertSession(endedAt: .now.addingTimeInterval(-30 * 60))
        // focus → break (1) → focus → break (2)
        harness.engine.skip()
        harness.engine.skip()
        harness.engine.skip()

        XCTAssertEqual(harness.engine.completedInCycle, 2)
        XCTAssertEqual(harness.engine.phase, .shortBreak)
        XCTAssertTrue(harness.engine.canStartNewCycle)
        XCTAssertEqual(sessionCount(), 1)

        harness.engine.startNewCycle()

        XCTAssertEqual(harness.engine.completedInCycle, 0)
        XCTAssertEqual(harness.engine.phase, .focus)
        XCTAssertTrue(harness.engine.isIdle)
        XCTAssertFalse(harness.engine.canStartNewCycle)
        XCTAssertEqual(sessionCount(), 1)
        XCTAssertEqual(harness.engine.cyclePosition, 1)
    }

    func testFreshFocusHasNoNewCycleAction() throws {
        harness = try QuietLockScreenHarness.make(style: .silent)
        XCTAssertFalse(harness.engine.canStartNewCycle)
        harness.engine.startNewCycle()
        XCTAssertEqual(harness.engine.phase, .focus)
        XCTAssertEqual(harness.engine.completedInCycle, 0)
    }

    func testIdleGroupExpiresAfterFourHours() throws {
        let engine = try makeRestoredEngine(
            completedInCycle: 2,
            phase: .shortBreak,
            lastActivity: .now.addingTimeInterval(-CycleGroupPolicy.inactivityLimit - 60),
            insertingSessionHoursAgo: 5
        )
        defer { engine.defaults.removePersistentDomain(forName: engine.suiteName) }

        XCTAssertEqual(engine.engine.completedInCycle, 0)
        XCTAssertEqual(engine.engine.phase, .focus)
        XCTAssertTrue(engine.engine.isIdle)
        XCTAssertEqual(engine.sessionCount, 1)
    }

    func testRecentGroupIsKept() throws {
        let engine = try makeRestoredEngine(
            completedInCycle: 2,
            phase: .shortBreak,
            lastActivity: .now.addingTimeInterval(-60 * 60),
            insertingSessionHoursAgo: 1
        )
        defer { engine.defaults.removePersistentDomain(forName: engine.suiteName) }

        XCTAssertEqual(engine.engine.completedInCycle, 2)
        XCTAssertEqual(engine.engine.phase, .shortBreak)
        XCTAssertEqual(engine.sessionCount, 1)
    }

    func testMissingLastActivityFallsBackToLastSession() throws {
        let engine = try makeRestoredEngine(
            completedInCycle: 2,
            phase: .shortBreak,
            lastActivity: nil,
            insertingSessionHoursAgo: 5
        )
        defer { engine.defaults.removePersistentDomain(forName: engine.suiteName) }

        XCTAssertEqual(engine.engine.completedInCycle, 0)
        XCTAssertEqual(engine.engine.phase, .focus)
        XCTAssertEqual(engine.sessionCount, 1)
    }

    func testStartAfterAStaleBreakBeginsAFreshFocus() throws {
        let restored = try makeRestoredEngine(
            completedInCycle: 2,
            phase: .shortBreak,
            lastActivity: .now.addingTimeInterval(-CycleGroupPolicy.inactivityLimit - 30),
            insertingSessionHoursAgo: 5
        )
        defer { restored.defaults.removePersistentDomain(forName: restored.suiteName) }

        restored.engine.start()

        XCTAssertEqual(restored.engine.phase, .focus)
        XCTAssertEqual(restored.engine.completedInCycle, 0)
        XCTAssertTrue(restored.engine.isRunning)
        XCTAssertEqual(restored.engine.cyclePosition, 1)
        XCTAssertEqual(restored.sessionCount, 1)
    }

    func testPausedGroupExpiresAfterFourHours() throws {
        let engine = try makeRestoredEngine(
            completedInCycle: 1,
            phase: .focus,
            lastActivity: .now.addingTimeInterval(-CycleGroupPolicy.inactivityLimit - 10),
            insertingSessionHoursAgo: 5,
            runState: "paused",
            pausedRemaining: 400
        )
        defer { engine.defaults.removePersistentDomain(forName: engine.suiteName) }

        XCTAssertEqual(engine.engine.completedInCycle, 0)
        XCTAssertEqual(engine.engine.phase, .focus)
        XCTAssertTrue(engine.engine.isIdle)
        XCTAssertEqual(engine.sessionCount, 1)
    }

    func testRunningTimerIsNotExpired() throws {
        let engine = try makeRestoredEngine(
            completedInCycle: 1,
            phase: .focus,
            lastActivity: .now.addingTimeInterval(-CycleGroupPolicy.inactivityLimit - 10),
            insertingSessionHoursAgo: 5,
            runState: "running",
            endDate: .now.addingTimeInterval(10 * 60)
        )
        defer { engine.defaults.removePersistentDomain(forName: engine.suiteName) }

        XCTAssertEqual(engine.engine.completedInCycle, 1)
        XCTAssertEqual(engine.engine.phase, .focus)
        XCTAssertTrue(engine.engine.isRunning)
        XCTAssertEqual(engine.sessionCount, 1)
    }

    func testLateCompletedFocusIsRecordedThenOpensANewGroup() throws {
        let engine = try makeRestoredEngine(
            completedInCycle: 1,
            phase: .focus,
            lastActivity: .now.addingTimeInterval(-5 * 60 * 60),
            insertingSessionHoursAgo: 6,
            runState: "running",
            endDate: .now.addingTimeInterval(-5 * 60 * 60)
        )
        defer { engine.defaults.removePersistentDomain(forName: engine.suiteName) }

        XCTAssertTrue(engine.engine.isAlarmPresented)
        XCTAssertEqual(engine.engine.finishedPhase, .focus)
        XCTAssertEqual(engine.engine.completedInCycle, 0)
        XCTAssertEqual(engine.engine.phase, .focus)
        XCTAssertEqual(engine.sessionCount, 2)
    }

    func testOnTimeCompletionStaysInTheSameGroup() throws {
        let engine = try makeRestoredEngine(
            completedInCycle: 1,
            phase: .focus,
            lastActivity: .now.addingTimeInterval(-25 * 60),
            insertingSessionHoursAgo: 1,
            runState: "running",
            endDate: .now.addingTimeInterval(-1)
        )
        defer { engine.defaults.removePersistentDomain(forName: engine.suiteName) }

        XCTAssertTrue(engine.engine.isAlarmPresented)
        XCTAssertEqual(engine.engine.completedInCycle, 2)
        XCTAssertEqual(engine.engine.phase, .shortBreak)
        XCTAssertEqual(engine.sessionCount, 2)
    }

    func testNewCycleDoesNothingWhileAlarmIsPresented() throws {
        let engine = try makeRestoredEngine(
            completedInCycle: 1,
            phase: .focus,
            lastActivity: .now.addingTimeInterval(-25 * 60),
            insertingSessionHoursAgo: 1,
            runState: "running",
            endDate: .now.addingTimeInterval(-1)
        )
        defer { engine.defaults.removePersistentDomain(forName: engine.suiteName) }

        XCTAssertTrue(engine.engine.isAlarmPresented)
        XCTAssertFalse(engine.engine.canStartNewCycle)
        engine.engine.startNewCycle()
        XCTAssertEqual(engine.engine.completedInCycle, 2)
        XCTAssertEqual(engine.engine.phase, .shortBreak)
    }

    // MARK: - Helpers

    private func insertSession(endedAt: Date, durationMinutes: Int = 25) {
        let session = PomodoroSession(endedAt: endedAt, durationMinutes: durationMinutes)
        harness.container.mainContext.insert(session)
        try? harness.container.mainContext.save()
    }

    private func sessionCount() -> Int {
        (try? harness.container.mainContext.fetchCount(FetchDescriptor<PomodoroSession>())) ?? 0
    }

    @MainActor
    private struct Restored {
        let engine: TimerEngine
        let defaults: UserDefaults
        let suiteName: String
        let container: ModelContainer

        var sessionCount: Int {
            (try? container.mainContext.fetchCount(FetchDescriptor<PomodoroSession>())) ?? 0
        }
    }

    private func makeRestoredEngine(
        completedInCycle: Int,
        phase: Phase,
        lastActivity: Date?,
        insertingSessionHoursAgo: Int?,
        runState: String = "idle",
        endDate: Date? = nil,
        pausedRemaining: TimeInterval? = nil
    ) throws -> Restored {
        let suiteName = "pomodoro.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(AlertStyle.silent.rawValue, forKey: "alertStyle")
        defaults.set(phase.rawValue, forKey: "engine.phase")
        defaults.set(completedInCycle, forKey: "engine.completedInCycle")
        defaults.set(runState, forKey: "engine.runState")
        if let lastActivity {
            defaults.set(lastActivity, forKey: "engine.lastCycleActivityAt")
        }
        if let endDate {
            defaults.set(endDate, forKey: "engine.endDate")
        }
        if let pausedRemaining {
            defaults.set(pausedRemaining, forKey: "engine.pausedRemaining")
        }

        let container = try ModelContainer(
            for: Schema([PomodoroSession.self]),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        if let insertingSessionHoursAgo {
            let session = PomodoroSession(
                endedAt: .now.addingTimeInterval(TimeInterval(-insertingSessionHoursAgo) * 60 * 60),
                durationMinutes: 25
            )
            container.mainContext.insert(session)
            try container.mainContext.save()
        }

        let engine = TimerEngine(
            settings: SettingsStore(defaults: defaults),
            modelContext: container.mainContext,
            defaults: defaults,
            alarmKit: FakeAlarmScheduler(),
            quietLockScreen: QuietLockScreenSpy()
        )
        return Restored(
            engine: engine,
            defaults: defaults,
            suiteName: suiteName,
            container: container
        )
    }
}
