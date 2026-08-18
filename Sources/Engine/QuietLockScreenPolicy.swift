import Foundation

/// What the app-owned lock-screen Live Activity should show right now.
///
/// AlarmKit already presents its own activity when a system alarm is armed,
/// so this snapshot is `.hidden` on that path. Quiet styles (and Loud when
/// AlarmKit is unavailable) get a running or paused countdown instead.
enum QuietLockScreenSnapshot: Equatable, Sendable {
    case hidden
    case running(phase: Phase, endDate: Date, totalDuration: TimeInterval)
    case paused(phase: Phase, remaining: TimeInterval, totalDuration: TimeInterval)
}

enum QuietLockScreenInputState: Equatable, Sendable {
    case idle
    case running(endDate: Date)
    case paused(remaining: TimeInterval)
}

enum QuietLockScreenPolicy {
    /// Decides lock-screen presence without touching ActivityKit or AlarmKit.
    ///
    /// - Parameter usesAlarmKitDisplay: True while a system alarm is armed,
    ///   or while Loud is still trying to arm one. Prevents a second activity
    ///   from stacking on top of AlarmKit's.
    static func snapshot(
        usesAlarmKitDisplay: Bool,
        timer: QuietLockScreenInputState,
        phase: Phase,
        isAlarmPresented: Bool,
        totalDuration: TimeInterval
    ) -> QuietLockScreenSnapshot {
        if isAlarmPresented || usesAlarmKitDisplay {
            return .hidden
        }
        switch timer {
        case .idle:
            return .hidden
        case .running(let endDate):
            return .running(phase: phase, endDate: endDate, totalDuration: totalDuration)
        case .paused(let remaining):
            return .paused(phase: phase, remaining: remaining, totalDuration: totalDuration)
        }
    }
}
