@preconcurrency import AlarmKit
import SwiftUI

/// Thin wrapper around `AlarmManager` (iOS 26 AlarmKit).
///
/// AlarmKit alarms are true system alarms: they present full-screen on the
/// lock screen and break through Silent mode and Focus at full volume —
/// unlike local notifications, which can be silently swallowed.
///
/// Because we schedule with a **countdown presentation**, AlarmKit also runs
/// a Live Activity for the countdown (rendered by the PomodoroWidgets
/// extension) on the Lock Screen and in the Dynamic Island, with pause /
/// resume controls. It appears when the alarm is scheduled and disappears
/// when it's cancelled or stopped.
@MainActor
final class AlarmScheduler {
    private let manager = AlarmManager.shared

    /// Returns true if we may schedule alarms, prompting the user if needed.
    func ensureAuthorization() async -> Bool {
        switch manager.authorizationState {
        case .authorized:
            return true
        case .notDetermined:
            return (try? await manager.requestAuthorization()) == .authorized
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    /// Schedules a countdown alarm that alerts after `seconds`.
    /// Returns the alarm id, or nil if scheduling failed.
    ///
    /// The ringing alert has a single button, labeled for the next step in
    /// the series ("Focus"/"Break"). AlarmKit requires the alert to have a
    /// stop button, so that button IS it: the system stops the alarm, then
    /// its `stopIntent` hook starts `nextUp` — whose fresh Live Activity
    /// takes over the lock screen immediately.
    func scheduleCountdown(
        seconds: TimeInterval,
        finishing phase: Phase,
        nextUp: Phase,
        sound: AlarmSound
    ) async -> UUID? {
        guard seconds > 0 else { return nil }
        let id = UUID()

        let alert = AlarmPresentation.Alert(
            title: phase == .focus ? "Time's up — focus complete" : "Break's over",
            stopButton: AlarmButton(
                text: nextUp == .focus ? "Focus" : "Break",
                textColor: .white,
                systemImageName: "play.fill"
            )
        )
        // Countdown + paused presentations opt this alarm into the Live
        // Activity (lock screen / Dynamic Island) and its pause support.
        let countdown = AlarmPresentation.Countdown(
            title: countdownTitle(for: phase),
            pauseButton: AlarmButton(
                text: "Pause",
                textColor: .white,
                systemImageName: "pause.fill"
            )
        )
        let paused = AlarmPresentation.Paused(
            title: "Paused",
            resumeButton: AlarmButton(
                text: "Resume",
                textColor: .white,
                systemImageName: "play.fill"
            )
        )
        let attributes = AlarmAttributes<PomodoroAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert, countdown: countdown, paused: paused),
            metadata: PomodoroAlarmMetadata(phase: phase),
            tintColor: Color.pomodoroOrange
        )
        let configuration = AlarmManager.AlarmConfiguration(
            countdownDuration: Alarm.CountdownDuration(preAlert: seconds, postAlert: nil),
            attributes: attributes,
            stopIntent: StartNextPhaseIntent(finishedPhase: phase, alarmID: id),
            sound: .named(sound.resourceName)
        )

        do {
            _ = try await manager.schedule(id: id, configuration: configuration)
            return id
        } catch {
            return nil
        }
    }

    private func countdownTitle(for phase: Phase) -> LocalizedStringResource {
        switch phase {
        case .focus: "Focusing"
        case .shortBreak: "Short break"
        case .longBreak: "Long break"
        }
    }

    /// Snapshot of every alarm this app currently has with the system.
    func allAlarms() -> [Alarm] {
        (try? manager.alarms) ?? []
    }

    /// Whether the alarm is still known to the system (counting down or alerting).
    func isActive(id: UUID) -> Bool {
        allAlarms().contains { $0.id == id }
    }

    /// The system's current state for the alarm, or nil if it no longer exists.
    func systemState(id: UUID) -> Alarm.State? {
        allAlarms().first { $0.id == id }?.state
    }

    /// Drops every alarm except `keep`. Prevents stacked countdowns when a
    /// previous schedule leaked (process death, racing `armAlarm` tasks).
    func cancelAll(except keep: UUID? = nil) {
        for alarm in allAlarms() where alarm.id != keep {
            dismiss(id: alarm.id, state: alarm.state)
        }
    }

    /// Cancels a countdown or stops a ringing alarm, whichever applies.
    func dismiss(id: UUID, state: Alarm.State? = nil) {
        let resolved = state ?? systemState(id: id)
        switch resolved {
        case .alerting:
            try? manager.stop(id: id)
        default:
            try? manager.cancel(id: id)
            try? manager.stop(id: id)
        }
    }

    /// Pauses a counting-down alarm (freezes the Live Activity countdown).
    func pause(id: UUID) {
        try? manager.pause(id: id)
    }

    /// Resumes a paused alarm.
    func resume(id: UUID) {
        try? manager.resume(id: id)
    }

    /// Cancels a pending (not yet fired) alarm. Also tears down its Live Activity.
    func cancel(id: UUID) {
        try? manager.cancel(id: id)
    }

    /// Stops a ringing alarm.
    func stop(id: UUID) {
        try? manager.stop(id: id)
    }

    /// Observes the system's alarm list and reports the alarms whenever
    /// anything changes — an alarm being removed (stopped/cancelled from the
    /// lock screen) or its state flipping between countdown and paused (the
    /// Live Activity's pause/resume buttons).
    func observeAlarms(
        _ handler: @escaping @MainActor ([Alarm]) -> Void
    ) -> Task<Void, Never> {
        let manager = self.manager
        return Task {
            for await alarms in manager.alarmUpdates {
                handler(alarms)
            }
        }
    }
}
