import ActivityKit
import Foundation

@MainActor
protocol QuietLiveActivityControlling: AnyObject {
    func sync(_ snapshot: QuietLockScreenSnapshot)
}

/// Starts, updates, and ends the app-owned Live Activity so Silent /
/// Headphones (and Loud-without-permission) still show a lock-screen
/// countdown without scheduling an AlarmKit alarm.
@MainActor
final class QuietLiveActivityController: QuietLiveActivityControlling {
    private var generation = 0

    func sync(_ snapshot: QuietLockScreenSnapshot) {
        generation += 1
        let gen = generation
        Task { @MainActor in
            guard gen == self.generation else { return }
            await apply(snapshot)
        }
    }

    private func apply(_ snapshot: QuietLockScreenSnapshot) async {
        switch snapshot {
        case .hidden:
            await endAll()
        case .running(let phase, let endDate, let totalDuration):
            await upsert(
                PomodoroActivityAttributes.ContentState(
                    phase: phase,
                    endDate: endDate,
                    totalDuration: totalDuration,
                    remainingWhenPaused: nil
                ),
                staleDate: endDate
            )
        case .paused(let phase, let remaining, let totalDuration):
            await upsert(
                PomodoroActivityAttributes.ContentState(
                    phase: phase,
                    endDate: Date.now.addingTimeInterval(remaining),
                    totalDuration: totalDuration,
                    remainingWhenPaused: remaining
                ),
                staleDate: nil
            )
        }
    }

    private func upsert(
        _ state: PomodoroActivityAttributes.ContentState,
        staleDate: Date?
    ) async {
        let content = ActivityContent(state: state, staleDate: staleDate)
        let existing = Activity<PomodoroActivityAttributes>.activities
        if let activity = existing.first {
            await activity.update(content)
            for extra in existing.dropFirst() {
                await extra.end(nil, dismissalPolicy: .immediate)
            }
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        _ = try? Activity.request(
            attributes: PomodoroActivityAttributes(),
            content: content,
            pushType: nil
        )
    }

    private func endAll() async {
        for activity in Activity<PomodoroActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
