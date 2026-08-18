import ActivityKit
import Foundation

/// App-owned Live Activity for styles that do not schedule AlarmKit
/// (Headphones, Silent, and Loud when alarm permission is denied).
///
/// Compiled into both the app and the widget: ActivityKit matches on the
/// type name, so both targets must see the same attributes.
struct PomodoroActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        var phase: Phase
        var endDate: Date
        var totalDuration: TimeInterval
        /// Non-nil means the countdown is frozen at this remaining time.
        var remainingWhenPaused: TimeInterval?

        var isPaused: Bool { remainingWhenPaused != nil }

        var lockScreenMode: PomodoroLockScreenMode {
            if let remainingWhenPaused {
                .paused(remaining: remainingWhenPaused, totalDuration: totalDuration)
            } else {
                .countdown(endDate: endDate, totalDuration: totalDuration)
            }
        }
    }
}

/// Shared countdown presentation used by both the AlarmKit widget and the
/// app-owned quiet Live Activity, so they look the same on the lock screen.
enum PomodoroLockScreenMode: Equatable, Sendable {
    case countdown(endDate: Date, totalDuration: TimeInterval)
    case paused(remaining: TimeInterval, totalDuration: TimeInterval)
    case finished
}
