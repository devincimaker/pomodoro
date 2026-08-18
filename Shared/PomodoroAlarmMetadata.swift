import AlarmKit

/// Custom payload attached to every AlarmKit alarm we schedule.
///
/// Compiled into BOTH the app and the widget extension: the Live Activity is
/// keyed on `AlarmAttributes<PomodoroAlarmMetadata>`, so the widget can only
/// decode alarms whose metadata type matches exactly.
nonisolated struct PomodoroAlarmMetadata: AlarmMetadata {
    /// The phase this countdown is running (drives labels in the widget).
    let phase: Phase

    init(phase: Phase = .focus) {
        self.phase = phase
    }
}
