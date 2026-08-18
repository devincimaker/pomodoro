import Foundation
import Observation
import SwiftData
import ActivityKit
@preconcurrency import AlarmKit

/// Drives the pomodoro state machine.
///
/// Timing is wall-clock based: while running we store only the `endDate` and
/// derive everything from it, so the timer never drifts across suspension.
///
/// Alerting has two paths:
/// 1. **AlarmKit (primary).** On start we schedule a system countdown alarm.
///    It rings at full volume through the lock screen, Silent mode, and Focus,
///    and keeps ringing until stopped — a true alarm, not a notification.
///    The system alarm is the source of truth for pause/resume/cancel. The
///    in-app clock only mirrors it. AlarmKit also owns the lock-screen
///    Live Activity on this path.
/// 2. **Fallback / quiet.** Headphones, Silent, and Loud-with-permission
///    denied do not schedule AlarmKit. A local notification covers the
///    locked-phone banner, and an app-owned Live Activity keeps the
///    countdown on the Lock Screen without a ringing alarm.
///
/// A foreground `Task` sleeping until `endDate` drives the in-app "Time's up"
/// takeover; it must never complete a phase while AlarmKit is still counting
/// or paused. `reconcileWithSystem()` covers reopening, process death, and
/// Live Activity controls.
@MainActor
@Observable
final class TimerEngine {
    /// The live engine instance, reachable by LiveActivityIntents — which the
    /// system executes in the app's process (launching it in the background
    /// if needed) when lock screen buttons are tapped.
    static weak var current: TimerEngine?

    enum State: Equatable {
        case idle
        case running(endDate: Date)
        case paused(remaining: TimeInterval)
    }

    // MARK: State

    private(set) var state: State = .idle
    private(set) var phase: Phase = .focus
    /// Focus blocks completed in the current cycle (0..<cadence).
    private(set) var completedInCycle = 0
    /// When true, the full-screen "Time's up" alarm takeover is presented.
    var isAlarmPresented = false
    /// The phase that just finished (drives copy on the Time's up screen).
    private(set) var finishedPhase: Phase = .focus

    private let settings: SettingsStore
    private let modelContext: ModelContext
    private let defaults: UserDefaults
    private let alarmKit: any AlarmScheduling
    private let quietLockScreen: any QuietLiveActivityControlling
    private let fallbackPlayer = AlarmPlayer()
    private var completionTask: Task<Void, Never>?
    private var alarmObservationTask: Task<Void, Never>?
    /// The AlarmKit alarm backing the current running phase, if any.
    private var currentAlarmID: UUID?
    /// Bumps on every new `armAlarm` so a stale schedule cannot overwrite
    /// a newer one (the old stacked-timer race).
    private var armGeneration = 0
    /// True while we are cancelling/scheduling so a transient empty alarm
    /// list is not treated as "user dismissed the Live Activity".
    private var isMutatingAlarms = false
    /// False while Loud is still trying to arm AlarmKit, so we do not flash
    /// an app-owned Live Activity on top of the system one.
    private var alarmKitAttempted = true

    init(
        settings: SettingsStore,
        modelContext: ModelContext,
        defaults: UserDefaults = .standard,
        alarmKit: any AlarmScheduling = AlarmScheduler(),
        quietLockScreen: any QuietLiveActivityControlling = QuietLiveActivityController()
    ) {
        self.settings = settings
        self.modelContext = modelContext
        self.defaults = defaults
        self.alarmKit = alarmKit
        self.quietLockScreen = quietLockScreen
        restorePersisted()
        alarmKitAttempted = true
        TimerEngine.current = self
        reconcileWithSystem()
        observeSystemAlarms()
        syncQuietLockScreen()
    }

    // MARK: Derived values

    var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    var isIdle: Bool { state == .idle }

    /// End date while running, nil otherwise.
    var endDate: Date? {
        if case .running(let endDate) = state { return endDate }
        return nil
    }

    /// True when we are running but the stored end date is stale (usually
    /// after a lock-screen pause/resume the process never observed).
    var hasStaleEndDate: Bool {
        guard case .running(let endDate) = state else { return false }
        return endDate <= .now
    }

    var remaining: TimeInterval {
        switch state {
        case .idle: settings.duration(for: phase)
        case .running(let endDate): max(0, endDate.timeIntervalSinceNow)
        case .paused(let remaining): remaining
        }
    }

    /// 0...1 progress through the current phase.
    var progress: Double {
        let total = settings.duration(for: phase)
        guard total > 0 else { return 0 }
        return min(1, max(0, 1 - remaining / total))
    }

    /// "Pomodoro 3 of 4" — 1-based position in the cycle.
    var cyclePosition: Int { min(completedInCycle + 1, settings.longBreakCadence) }

    var focusBlocksUntilLongBreak: Int {
        max(0, settings.longBreakCadence - completedInCycle)
    }

    /// What comes after the current phase, given cycle position.
    var nextPhase: Phase {
        switch phase {
        case .focus:
            (completedInCycle + 1) >= settings.longBreakCadence ? .longBreak : .shortBreak
        case .shortBreak, .longBreak:
            .focus
        }
    }

    // MARK: Controls

    func start() {
        guard !isRunning else { return }
        let duration: TimeInterval
        let resuming: Bool
        if case .paused(let remaining) = state {
            duration = remaining
            resuming = true
        } else {
            duration = settings.duration(for: phase)
            resuming = false
        }

        if resuming, let id = currentAlarmID, alarmKit.systemState(id: id) == .paused {
            let endDate = Date.now.addingTimeInterval(duration)
            applyRunning(endDate: endDate)
            alarmKit.resume(id: id)
            syncQuietLockScreen()
            return
        }

        alarmKitAttempted = !settings.alertStyle.usesAlarmKit
        let endDate = Date.now.addingTimeInterval(duration)
        applyRunning(endDate: endDate)
        syncQuietLockScreen()
        Task { await armAlarm(seconds: duration) }
    }

    func pause() {
        guard case .running(let endDate) = state else { return }
        applyPaused(remaining: max(0, endDate.timeIntervalSinceNow))
        NotificationManager.shared.cancelEndNotification()
        if let id = currentAlarmID {
            alarmKit.pause(id: id)
        }
        syncQuietLockScreen()
    }

    func togglePlayPause() {
        isRunning ? pause() : start()
    }

    /// Restart the current phase from the top.
    func reset() {
        abandonPhase(cancelAlarm: true)
    }

    /// Advance to the next phase without ringing and without recording a session.
    func skip() {
        abandonPhase(cancelAlarm: true)
        advance(recording: false)
        persist()
    }

    /// Stop the ringing alarm and arm the next phase (does not auto-start).
    func stopAlarm() {
        if let id = currentAlarmID {
            alarmKit.stop(id: id)
            currentAlarmID = nil
        }
        fallbackPlayer.stop()
        isAlarmPresented = false
        persist()
        syncQuietLockScreen()
    }

    /// Called on scene activation: adopt whatever AlarmKit is doing, including
    /// a pause/resume that happened while we were suspended or dead.
    func checkForCompletion() {
        reconcileWithSystem()
        completeIfQuietDeadlinePassed()
    }

    /// Re-arm alerts after the user changes Loud / Headphones / Silent.
    /// Loud → quiet drops any system alarm so it cannot siren the room.
    /// Quiet → Loud schedules AlarmKit for the remaining time.
    func handleAlertStyleDidChange() {
        if isAlarmPresented {
            if let id = currentAlarmID {
                alarmKit.stop(id: id)
                currentAlarmID = nil
            }
            fallbackPlayer.stop()
        }

        switch settings.alertStyle {
        case .loud:
            NotificationManager.shared.cancelEndNotification()
            alarmKitAttempted = false
            guard case .running(let endDate) = state else {
                persist()
                syncQuietLockScreen()
                return
            }
            let remaining = endDate.timeIntervalSinceNow
            guard remaining > 1 else {
                persist()
                syncQuietLockScreen()
                return
            }
            syncQuietLockScreen()
            Task { await armAlarm(seconds: remaining) }
        case .headphones, .silent:
            isMutatingAlarms = true
            if let id = currentAlarmID {
                alarmKit.dismiss(id: id, state: nil)
                currentAlarmID = nil
            }
            alarmKit.cancelAll(except: nil)
            isMutatingAlarms = false
            alarmKitAttempted = true
            if case .running(let endDate) = state {
                NotificationManager.shared.requestAuthorizationIfNeeded()
                NotificationManager.shared.scheduleEndNotification(
                    at: endDate,
                    finishing: phase,
                    sound: nil
                )
            }
            persist()
            syncQuietLockScreen()
        }
    }

    /// Re-read AlarmKit + the Live Activity presentation and make in-app
    /// state match. Safe to call at any time; it is idempotent.
    func reconcileWithSystem() {
        let alarms = alarmKit.allAlarms()
        reconcile(with: alarms)
        completeIfQuietDeadlinePassed()
    }

    /// Entry point for the Live Activity stop button (and swipe-to-dismiss
    /// after the system has already torn the alarm down).
    func handleLiveActivityStop(alarmID: UUID) {
        if currentAlarmID == nil || currentAlarmID == alarmID {
            abandonPhase(cancelAlarm: true, alarmID: alarmID)
        } else {
            alarmKit.dismiss(id: alarmID, state: nil)
        }
    }

    /// Entry point for the lock screen chaining intent: the ringing alert's
    /// single button ("Focus"/"Break") stops the alarm and starts the next
    /// block in the series.
    ///
    /// Runs in the app's process (the system launches it in the background
    /// if needed), so the engine stays the single source of truth for cycle
    /// bookkeeping and session recording.
    func handleLockScreenAdvance(finishedRaw: String, alarmID: UUID) async {
        guard let finished = Phase(rawValue: finishedRaw) else {
            alarmKit.dismiss(id: alarmID, state: nil)
            return
        }

        // 1. Account for the finished block. The alarm having rung is ground
        // truth that `finished` fully elapsed, so reconcile whatever
        // in-memory state we have with that fact — it can be stale in ways
        // the observer never got to sync (e.g. a lock-screen resume intent
        // woke the app so briefly that the process re-suspended before the
        // alarmUpdates observer ran, leaving the engine frozen at .paused).
        if phase == finished {
            switch state {
            case .running:
                complete(force: true)
            case .idle, .paused:
                completionTask?.cancel()
                completionTask = nil
                finishedPhase = finished
                advance(recording: true)
            }
        }

        // 2. Silence the alarm and tear down any ringing state.
        alarmKit.dismiss(id: alarmID, state: nil)
        if currentAlarmID == alarmID { currentAlarmID = nil }
        fallbackPlayer.stop()
        isAlarmPresented = false

        // 3. Start the next phase; its alarm brings a fresh Live Activity.
        guard state == .idle else {
            persist()
            return
        }
        let duration = settings.duration(for: phase)
        applyRunning(endDate: Date.now.addingTimeInterval(duration))
        await armAlarm(seconds: duration)
    }

    // MARK: Alarm arming

    private func armAlarm(seconds: TimeInterval) async {
        armGeneration += 1
        let gen = armGeneration
        isMutatingAlarms = true
        defer {
            if gen == armGeneration {
                isMutatingAlarms = false
                alarmKitAttempted = true
                syncQuietLockScreen()
            }
        }

        alarmKit.cancelAll(except: nil)
        currentAlarmID = nil

        if !settings.alertStyle.usesAlarmKit {
            guard gen == armGeneration, case .running(let endDate) = state else { return }
            NotificationManager.shared.requestAuthorizationIfNeeded()
            NotificationManager.shared.scheduleEndNotification(
                at: endDate,
                finishing: phase,
                sound: nil
            )
            persist()
            return
        }

        guard await alarmKit.ensureAuthorization() else {
            guard gen == armGeneration, case .running(let endDate) = state else { return }
            NotificationManager.shared.requestAuthorizationIfNeeded()
            NotificationManager.shared.scheduleEndNotification(at: endDate, finishing: phase)
            persist()
            return
        }
        guard gen == armGeneration else { return }

        if let id = await alarmKit.scheduleCountdown(
            seconds: seconds,
            finishing: phase,
            nextUp: nextPhase,
            sound: settings.alarmSound
        ) {
            guard gen == armGeneration else {
                alarmKit.dismiss(id: id, state: nil)
                return
            }
            currentAlarmID = id
            persist()
            return
        }

        guard gen == armGeneration, case .running(let endDate) = state else { return }
        NotificationManager.shared.requestAuthorizationIfNeeded()
        NotificationManager.shared.scheduleEndNotification(at: endDate, finishing: phase)
        persist()
    }

    /// Keeps in-app state in sync with the system alarm:
    /// - Ringing alarm stopped from the lock screen → dismiss our takeover.
    /// - Countdown paused/resumed/cancelled from the Live Activity → mirror
    ///   it, using the Live Activity fire date so we don't invent remaining.
    private func observeSystemAlarms() {
        alarmObservationTask = alarmKit.observeAlarms { [weak self] alarms in
            self?.reconcile(with: alarms)
        }
    }

    private func reconcile(with alarms: [Alarm]) {
        // Drop leftovers so a leaked schedule cannot ring later.
        if let keep = pickCanonicalAlarm(from: alarms) {
            for alarm in alarms where alarm.id != keep.id {
                alarmKit.dismiss(id: alarm.id, state: alarm.state)
            }
            adopt(keep)
            return
        }

        // No system alarm. If we were mid-schedule, ignore the empty snapshot.
        if isMutatingAlarms { return }

        if currentAlarmID != nil {
            if isAlarmPresented {
                fallbackPlayer.stop()
                isAlarmPresented = false
                currentAlarmID = nil
                persist()
            } else {
                // User dismissed the Live Activity (or the system cancelled
                // it). That is a stop, not a completed block.
                abandonPhase(cancelAlarm: false)
            }
        }
    }

    /// Prefer the persisted id; otherwise the one that is still doing work.
    private func pickCanonicalAlarm(from alarms: [Alarm]) -> Alarm? {
        if let id = currentAlarmID, let match = alarms.first(where: { $0.id == id }) {
            return match
        }
        return alarms.first { alarm in
            switch alarm.state {
            case .countdown, .paused, .alerting: true
            default: false
            }
        }
    }

    private func adopt(_ alarm: Alarm) {
        currentAlarmID = alarm.id

        switch alarm.state {
        case .paused:
            let remaining = presentationRemaining(for: alarm.id)
                ?? pausedRemainingFallback()
            applyPaused(remaining: remaining)
        case .countdown:
            if let fireDate = presentationFireDate(for: alarm.id), fireDate > .now {
                applyRunning(endDate: fireDate)
            } else if case .paused(let remaining) = state, remaining > 0 {
                applyRunning(endDate: Date.now.addingTimeInterval(remaining))
            } else if case .running(let endDate) = state, endDate > .now {
                scheduleCompletion(at: endDate)
            } else {
                // Still counting on the system, but we don't know the fire
                // date yet. Stay running without a deadline that would
                // complete the phase early; retry once the activity appears.
                if case .running = state {
                    completionTask?.cancel()
                    completionTask = nil
                } else {
                    state = .running(endDate: .now)
                    completionTask?.cancel()
                    completionTask = nil
                }
                persist()
                retryPresentationSync()
            }
        case .alerting:
            if case .running = state {
                complete(force: true)
            } else if !isAlarmPresented {
                // Process died while the alarm was ringing, or we missed the
                // running→complete transition. Treat the ring as elapsed.
                if phase == (presentationPhase(for: alarm.id) ?? phase) {
                    finishedPhase = phase
                    if case .idle = state {
                        advance(recording: true)
                    }
                }
                isAlarmPresented = true
                persist()
            }
        default:
            break
        }
    }

    private func retryPresentationSync() {
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            self?.reconcileWithSystem()
        }
    }

    // MARK: Live Activity presentation (the only live remaining-time source)

    private func presentationMode(for alarmID: UUID) -> AlarmPresentationState.Mode? {
        for activity in Activity<AlarmAttributes<PomodoroAlarmMetadata>>.activities {
            if activity.content.state.alarmID == alarmID {
                return activity.content.state.mode
            }
        }
        return nil
    }

    private func presentationFireDate(for alarmID: UUID) -> Date? {
        guard case .countdown(let countdown) = presentationMode(for: alarmID) else { return nil }
        return countdown.fireDate
    }

    private func presentationRemaining(for alarmID: UUID) -> TimeInterval? {
        switch presentationMode(for: alarmID) {
        case .paused(let paused):
            return max(0, paused.totalCountdownDuration - paused.previouslyElapsedDuration)
        case .countdown(let countdown):
            return max(0, countdown.fireDate.timeIntervalSinceNow)
        default:
            return nil
        }
    }

    private func presentationPhase(for alarmID: UUID) -> Phase? {
        for activity in Activity<AlarmAttributes<PomodoroAlarmMetadata>>.activities {
            if activity.content.state.alarmID == alarmID {
                return activity.attributes.metadata?.phase
            }
        }
        return nil
    }

    private func pausedRemainingFallback() -> TimeInterval {
        switch state {
        case .paused(let remaining): remaining
        case .running(let endDate) where endDate > .now: endDate.timeIntervalSinceNow
        default: 0
        }
    }

    // MARK: Internals

    private func applyRunning(endDate: Date) {
        state = .running(endDate: endDate)
        scheduleCompletion(at: endDate)
        persist()
    }

    private func applyPaused(remaining: TimeInterval) {
        completionTask?.cancel()
        completionTask = nil
        state = .paused(remaining: max(0, remaining))
        persist()
    }

    private func abandonPhase(cancelAlarm: Bool, alarmID: UUID? = nil) {
        armGeneration += 1
        completionTask?.cancel()
        completionTask = nil
        NotificationManager.shared.cancelEndNotification()
        fallbackPlayer.stop()
        isAlarmPresented = false
        if cancelAlarm {
            if let id = currentAlarmID ?? alarmID {
                alarmKit.dismiss(id: id, state: nil)
            }
            alarmKit.cancelAll(except: nil)
        }
        currentAlarmID = nil
        state = .idle
        persist()
        syncQuietLockScreen()
    }

    private func scheduleCompletion(at endDate: Date) {
        completionTask?.cancel()
        completionTask = Task { [weak self] in
            let interval = endDate.timeIntervalSinceNow
            if interval > 0 {
                try? await Task.sleep(for: .seconds(interval))
            }
            guard !Task.isCancelled else { return }
            self?.handleForegroundDeadline()
        }
    }

    /// In-app deadline fired. AlarmKit still owns the real clock: if the
    /// system alarm is counting or paused, this endDate is stale and we
    /// must not complete (that was the "doesn't continue / stacks timers"
    /// bug after a Live Activity pause).
    private func handleForegroundDeadline() {
        if let id = currentAlarmID {
            switch alarmKit.systemState(id: id) {
            case .countdown, .paused:
                reconcileWithSystem()
                return
            case .alerting:
                complete(force: true)
                return
            case .none:
                abandonPhase(cancelAlarm: false)
                return
            default:
                break
            }
        }
        complete(force: false)
    }

    private func complete(force: Bool) {
        guard case .running = state else { return }

        if !force, let id = currentAlarmID {
            switch alarmKit.systemState(id: id) {
            case .countdown, .paused:
                return
            default:
                break
            }
        }

        completionTask?.cancel()
        completionTask = nil
        NotificationManager.shared.cancelEndNotification()
        finishedPhase = phase
        advance(recording: true)
        presentCompletionAlert()
        persist()
        syncQuietLockScreen()
    }

    private func presentCompletionAlert() {
        switch settings.alertStyle {
        case .loud:
            if let id = currentAlarmID {
                if alarmKit.isActive(id: id) {
                    isAlarmPresented = true
                } else {
                    currentAlarmID = nil
                    isAlarmPresented = true
                    fallbackPlayer.start(sound: settings.alarmSound)
                }
            } else {
                isAlarmPresented = true
                fallbackPlayer.start(sound: settings.alarmSound)
            }
        case .headphones:
            isAlarmPresented = true
            if AudioRoute.isPrivateListening {
                fallbackPlayer.playOnce(sound: settings.alarmSound)
            } else {
                HapticCue.phaseEnded()
            }
        case .silent:
            isAlarmPresented = true
            HapticCue.phaseEnded()
        }
    }

    /// Quiet styles (and the permission-denied Loud fallback) have no
    /// AlarmKit clock. If the app was suspended past `endDate`, complete now.
    private func completeIfQuietDeadlinePassed() {
        guard case .running(let endDate) = state, endDate <= .now, !isAlarmPresented else { return }
        if let id = currentAlarmID {
            switch alarmKit.systemState(id: id) {
            case .countdown, .paused:
                return
            case .alerting:
                complete(force: true)
            default:
                complete(force: true)
            }
        } else {
            complete(force: true)
        }
    }

    private func advance(recording: Bool) {
        if phase == .focus {
            if recording {
                let session = PomodoroSession(durationMinutes: settings.focusMinutes)
                modelContext.insert(session)
                try? modelContext.save()
            }
            completedInCycle += 1
            phase = completedInCycle >= settings.longBreakCadence ? .longBreak : .shortBreak
        } else {
            if phase == .longBreak {
                completedInCycle = 0
            }
            phase = .focus
        }
        state = .idle
    }

    /// Count of focus sessions completed today (for the Time's up screen).
    func sessionsCompletedToday() -> Int {
        let startOfDay = Calendar.current.startOfDay(for: .now)
        let descriptor = FetchDescriptor<PomodoroSession>(
            predicate: #Predicate { $0.endedAt >= startOfDay }
        )
        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }

    // MARK: Persistence

    /// Survives process death so we can re-attach to an AlarmKit countdown
    /// instead of scheduling a second one on the next Start tap.
    private enum PersistKey {
        static let phase = "engine.phase"
        static let completedInCycle = "engine.completedInCycle"
        static let currentAlarmID = "engine.currentAlarmID"
        static let finishedPhase = "engine.finishedPhase"
        static let endDate = "engine.endDate"
        static let pausedRemaining = "engine.pausedRemaining"
        static let runState = "engine.runState"
        static let isAlarmPresented = "engine.isAlarmPresented"
    }

    /// App-owned lock-screen activity, used when AlarmKit is not presenting.
    private var usesAlarmKitDisplay: Bool {
        currentAlarmID != nil || (settings.alertStyle.usesAlarmKit && !alarmKitAttempted)
    }

    private func syncQuietLockScreen() {
        let timer: QuietLockScreenInputState
        switch state {
        case .idle:
            timer = .idle
        case .running(let endDate):
            timer = .running(endDate: endDate)
        case .paused(let remaining):
            timer = .paused(remaining: remaining)
        }
        quietLockScreen.sync(
            QuietLockScreenPolicy.snapshot(
                usesAlarmKitDisplay: usesAlarmKitDisplay,
                timer: timer,
                phase: phase,
                isAlarmPresented: isAlarmPresented,
                totalDuration: settings.duration(for: phase)
            )
        )
    }

    private func persist() {
        defaults.set(phase.rawValue, forKey: PersistKey.phase)
        defaults.set(completedInCycle, forKey: PersistKey.completedInCycle)
        defaults.set(finishedPhase.rawValue, forKey: PersistKey.finishedPhase)
        defaults.set(isAlarmPresented, forKey: PersistKey.isAlarmPresented)
        if let currentAlarmID {
            defaults.set(currentAlarmID.uuidString, forKey: PersistKey.currentAlarmID)
        } else {
            defaults.removeObject(forKey: PersistKey.currentAlarmID)
        }
        switch state {
        case .idle:
            defaults.set("idle", forKey: PersistKey.runState)
            defaults.removeObject(forKey: PersistKey.endDate)
            defaults.removeObject(forKey: PersistKey.pausedRemaining)
        case .running(let endDate):
            defaults.set("running", forKey: PersistKey.runState)
            defaults.set(endDate, forKey: PersistKey.endDate)
            defaults.removeObject(forKey: PersistKey.pausedRemaining)
        case .paused(let remaining):
            defaults.set("paused", forKey: PersistKey.runState)
            defaults.set(remaining, forKey: PersistKey.pausedRemaining)
            defaults.removeObject(forKey: PersistKey.endDate)
        }
    }

    private func restorePersisted() {
        if let raw = defaults.string(forKey: PersistKey.phase),
           let restored = Phase(rawValue: raw) {
            phase = restored
        }
        completedInCycle = defaults.integer(forKey: PersistKey.completedInCycle)
        if let raw = defaults.string(forKey: PersistKey.finishedPhase),
           let restored = Phase(rawValue: raw) {
            finishedPhase = restored
        }
        isAlarmPresented = defaults.bool(forKey: PersistKey.isAlarmPresented)
        if let raw = defaults.string(forKey: PersistKey.currentAlarmID),
           let id = UUID(uuidString: raw) {
            currentAlarmID = id
        }
        switch defaults.string(forKey: PersistKey.runState) {
        case "running":
            if let endDate = defaults.object(forKey: PersistKey.endDate) as? Date {
                state = .running(endDate: endDate)
            }
        case "paused":
            state = .paused(remaining: defaults.double(forKey: PersistKey.pausedRemaining))
        default:
            state = .idle
        }
    }
}
