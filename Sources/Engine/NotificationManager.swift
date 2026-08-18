import Foundation
import UserNotifications

/// Schedules the "time's up" local notification so the user is alerted even
/// when the app is backgrounded or the device is locked.
@MainActor
final class NotificationManager {
    static let shared = NotificationManager()
    private static let endNotificationID = "phase-end"
    private var hasRequestedAuth = false

    private init() {}

    func requestAuthorizationIfNeeded() {
        guard !hasRequestedAuth else { return }
        hasRequestedAuth = true
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
            }
        }
    }

    func scheduleEndNotification(
        at endDate: Date,
        finishing phase: Phase,
        sound: UNNotificationSound? = .default
    ) {
        cancelEndNotification()
        let interval = endDate.timeIntervalSinceNow
        guard interval > 1 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Time's up"
        content.body = phase == .focus
            ? "Focus session complete. Time for a break."
            : "Break's over. Ready for the next focus block?"
        content.sound = sound
        content.interruptionLevel = .timeSensitive

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(
            identifier: Self.endNotificationID,
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }

    func cancelEndNotification() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [Self.endNotificationID])
    }
}
