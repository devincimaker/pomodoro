import AppIntents
import Foundation
@preconcurrency import AlarmKit

/// App intents backing the buttons on the Live Activity (Lock Screen +
/// Dynamic Island). They talk straight to `AlarmManager`; the app — if it's
/// alive — hears about the change through `alarmUpdates` and syncs its own
/// `TimerEngine` state (see `TimerEngine.observeSystemAlarms`).
///
/// Included in both the app and the widget target: the widget needs the type
/// to build the button, the app needs it so the intent can execute in the
/// app's process.

struct PausePomodoroIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pause Pomodoro"
    static let description = IntentDescription("Pauses the running pomodoro countdown.")
    static let isDiscoverable = false

    @Parameter(title: "Alarm ID") var alarmID: String

    init(alarmID: UUID) { self.alarmID = alarmID.uuidString }
    init() { self.alarmID = "" }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: alarmID) {
            try? AlarmManager.shared.pause(id: id)
        }
        return .result()
    }
}

struct ResumePomodoroIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Resume Pomodoro"
    static let description = IntentDescription("Resumes the paused pomodoro countdown.")
    static let isDiscoverable = false

    @Parameter(title: "Alarm ID") var alarmID: String

    init(alarmID: UUID) { self.alarmID = alarmID.uuidString }
    init() { self.alarmID = "" }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: alarmID) {
            try? AlarmManager.shared.resume(id: id)
        }
        return .result()
    }
}

/// Cancels the running/paused countdown from the Live Activity. Unlike pause,
/// this tears the system alarm down so it cannot keep counting or stack.
struct StopPomodoroIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop Pomodoro"
    static let description = IntentDescription("Stops the pomodoro countdown and dismisses the timer.")
    static let isDiscoverable = false

    @Parameter(title: "Alarm ID") var alarmID: String

    init(alarmID: UUID) { self.alarmID = alarmID.uuidString }
    init() { self.alarmID = "" }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: alarmID) else { return .result() }
        #if POMODORO_WIDGET
        try? AlarmManager.shared.cancel(id: id)
        try? AlarmManager.shared.stop(id: id)
        #else
        var engine = await TimerEngine.current
        if engine == nil {
            try? await Task.sleep(for: .milliseconds(300))
            engine = await TimerEngine.current
        }
        if let engine {
            await engine.handleLiveActivityStop(alarmID: id)
        } else {
            try? AlarmManager.shared.cancel(id: id)
            try? AlarmManager.shared.stop(id: id)
        }
        #endif
        return .result()
    }
}

/// The single action while the alarm is RINGING: stop it and immediately
/// start the next block in the series (break → focus, focus → short/long
/// break). Wired to the system alert's stop button (labeled "Focus"/"Break"
/// via its stopIntent hook) and the widget's play button.
struct StartNextPhaseIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Start Next Phase"
    static let description = IntentDescription("Stops the alarm and starts the next pomodoro phase.")
    static let isDiscoverable = false

    @Parameter(title: "Finished Phase") var finishedPhase: String
    @Parameter(title: "Alarm ID") var alarmID: String

    init(finishedPhase: Phase, alarmID: UUID) {
        self.finishedPhase = finishedPhase.rawValue
        self.alarmID = alarmID.uuidString
    }
    init() {
        self.finishedPhase = ""
        self.alarmID = ""
    }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: alarmID) else { return .result() }
        #if POMODORO_WIDGET
        // Never executed here — safety net if the system ever runs it
        // in-extension.
        try? AlarmManager.shared.stop(id: id)
        #else
        // LiveActivityIntents perform in the APP's process (the widget only
        // compiles the type to render buttons), so the engine is reachable.
        // On a cold background launch the engine registers itself during app
        // init; give it a beat if the intent got in first.
        var engine = await TimerEngine.current
        if engine == nil {
            try? await Task.sleep(for: .milliseconds(300))
            engine = await TimerEngine.current
        }
        if let engine {
            await engine.handleLockScreenAdvance(finishedRaw: finishedPhase, alarmID: id)
        } else {
            // Engine unavailable for some reason: at least silence the alarm.
            try? AlarmManager.shared.stop(id: id)
        }
        #endif
        return .result()
    }
}

// MARK: - Quiet (app-owned) Live Activity

/// Pause / resume / stop for the app-owned lock-screen activity used when
/// AlarmKit is not scheduled. These run in the app process and talk to
/// `TimerEngine` directly — there is no system alarm to drive.

struct PauseQuietPomodoroIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pause Pomodoro"
    static let description = IntentDescription("Pauses the running pomodoro countdown.")
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        #if !POMODORO_WIDGET
        await resolveEngine()?.pause()
        #endif
        return .result()
    }
}

struct ResumeQuietPomodoroIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Resume Pomodoro"
    static let description = IntentDescription("Resumes the paused pomodoro countdown.")
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        #if !POMODORO_WIDGET
        await resolveEngine()?.start()
        #endif
        return .result()
    }
}

struct StopQuietPomodoroIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop Pomodoro"
    static let description = IntentDescription("Stops the pomodoro countdown and dismisses the timer.")
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        #if !POMODORO_WIDGET
        await resolveEngine()?.reset()
        #endif
        return .result()
    }
}

#if !POMODORO_WIDGET
@MainActor
private func resolveEngine() async -> TimerEngine? {
    if let engine = TimerEngine.current { return engine }
    try? await Task.sleep(for: .milliseconds(300))
    return TimerEngine.current
}
#endif
