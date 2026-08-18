import Foundation

/// When a stretch of pomodoros counts as one short-break / long-break group.
///
/// Recorded focus sessions always stay in Progress. This only decides whether
/// the next block continues the current cadence or starts at pomodoro 1 of N.
enum CycleGroupPolicy {
    /// Idle time after which the next focus opens a new group.
    /// Matches the POM-9 example: two pomodoros in the morning should not
    /// still be "3 of 4" when you sit down again hours later.
    static let inactivityLimit: TimeInterval = 4 * 60 * 60

    /// True when the user can close the current group by hand.
    static func canStartNewCycle(
        completedInCycle: Int,
        phase: Phase,
        isAlarmPresented: Bool
    ) -> Bool {
        !isAlarmPresented && (completedInCycle > 0 || phase != .focus)
    }

    /// True when the current cadence is stale and should reset to a fresh
    /// focus block. A still-counting timer is left alone.
    static func shouldStartNewGroup(
        lastActivityAt: Date?,
        now: Date,
        isActivelyTiming: Bool,
        inactivityLimit: TimeInterval = inactivityLimit
    ) -> Bool {
        guard !isActivelyTiming, let lastActivityAt else { return false }
        return now.timeIntervalSince(lastActivityAt) >= inactivityLimit
    }
}
