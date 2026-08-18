import Foundation
import SwiftData

/// One completed focus block. Only fully elapsed focus sessions are recorded —
/// skipped or reset sessions never touch the store.
@Model
final class PomodoroSession {
    var endedAt: Date
    var durationMinutes: Int

    init(endedAt: Date = .now, durationMinutes: Int) {
        self.endedAt = endedAt
        self.durationMinutes = durationMinutes
    }
}
