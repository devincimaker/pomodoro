import Foundation
import SwiftData
import XCTest
@preconcurrency import AlarmKit
@testable import Pomodoro

@MainActor
final class QuietLockScreenSpy: QuietLiveActivityControlling {
    private(set) var snapshots: [QuietLockScreenSnapshot] = []

    var current: QuietLockScreenSnapshot { snapshots.last ?? .hidden }

    func sync(_ snapshot: QuietLockScreenSnapshot) {
        snapshots.append(snapshot)
    }
}

@MainActor
final class FakeAlarmScheduler: AlarmScheduling {
    var authorizationGranted = false
    private(set) var scheduledCountdowns: [(seconds: TimeInterval, finishing: Phase)] = []
    private(set) var activeIDs: Set<UUID> = []

    func ensureAuthorization() async -> Bool { authorizationGranted }

    func scheduleCountdown(
        seconds: TimeInterval,
        finishing phase: Phase,
        nextUp: Phase,
        sound: AlarmSound
    ) async -> UUID? {
        guard authorizationGranted else { return nil }
        let id = UUID()
        scheduledCountdowns.append((seconds, phase))
        activeIDs.insert(id)
        return id
    }

    func allAlarms() -> [Alarm] { [] }
    func isActive(id: UUID) -> Bool { activeIDs.contains(id) }
    func systemState(id: UUID) -> Alarm.State? {
        activeIDs.contains(id) ? .countdown : nil
    }

    func cancelAll(except keep: UUID?) {
        if let keep, activeIDs.contains(keep) {
            activeIDs = [keep]
        } else {
            activeIDs.removeAll()
        }
    }

    func dismiss(id: UUID, state: Alarm.State?) { activeIDs.remove(id) }
    func pause(id: UUID) {}
    func resume(id: UUID) {}
    func cancel(id: UUID) { activeIDs.remove(id) }
    func stop(id: UUID) { activeIDs.remove(id) }

    func observeAlarms(
        _ handler: @escaping @MainActor ([Alarm]) -> Void
    ) -> Task<Void, Never> {
        Task {}
    }
}

@MainActor
struct QuietLockScreenHarness {
    let engine: TimerEngine
    let spy: QuietLockScreenSpy
    let alarms: FakeAlarmScheduler
    let settings: SettingsStore
    let defaults: UserDefaults
    let suiteName: String
    let container: ModelContainer

    static func make(
        style: AlertStyle = .silent,
        alarmAuthorization: Bool = false
    ) throws -> QuietLockScreenHarness {
        let suiteName = "pomodoro.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = SettingsStore(defaults: defaults)
        settings.alertStyle = style
        let container = try ModelContainer(
            for: Schema([PomodoroSession.self]),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let spy = QuietLockScreenSpy()
        let alarms = FakeAlarmScheduler()
        alarms.authorizationGranted = alarmAuthorization
        let engine = TimerEngine(
            settings: settings,
            modelContext: container.mainContext,
            defaults: defaults,
            alarmKit: alarms,
            quietLockScreen: spy
        )
        return QuietLockScreenHarness(
            engine: engine,
            spy: spy,
            alarms: alarms,
            settings: settings,
            defaults: defaults,
            suiteName: suiteName,
            container: container
        )
    }

    func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func settle() async {
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(80))
    }
}

extension QuietLockScreenSnapshot {
    func assertRunning(
        phase: Phase = .focus,
        totalDuration: TimeInterval = 25 * 60,
        remainingAccuracy: TimeInterval = 1.5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .running(let actualPhase, let endDate, let total) = self else {
            XCTFail("expected running snapshot, got \(self)", file: file, line: line)
            return
        }
        XCTAssertEqual(actualPhase, phase, file: file, line: line)
        XCTAssertEqual(total, totalDuration, file: file, line: line)
        XCTAssertEqual(endDate.timeIntervalSinceNow, totalDuration, accuracy: remainingAccuracy, file: file, line: line)
    }
}
