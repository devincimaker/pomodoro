# Pomodoro

Native SwiftUI pomodoro work tracker for iPhone. Swift 6, strict concurrency, **iOS 26+** (AlarmKit). Requires Xcode 26.

## Run it

```bash
cd Pomodoro
xcodegen generate      # brew install xcodegen if you don't have it
open Pomodoro.xcodeproj
```

Pick a simulator (or your device + your team in Signing & Capabilities) and hit Run.

No dependencies. Alarm sounds are bundled WAVs (generated offline) used by the AlarmKit system alarm; the in-app fallback synthesizes the same tones with AVAudioEngine.

## Structure

```
Sources/
  PomodoroApp.swift          App entry, SwiftData container, scene-phase hook
  Models/
    SettingsStore.swift      @Observable, UserDefaults-backed
    PomodoroSession.swift    SwiftData model (completed focus blocks only)
  Engine/
    TimerEngine.swift        Wall-clock state machine (idle/running/paused)
    AlarmScheduler.swift     AlarmKit wrapper: system alarms that break through
    AlarmPlayer.swift        Fallback in-app alarm (permission denied case)
    NotificationManager.swift Fallback local notification (permission denied case)
  Views/
    RootView.swift           3-tab TabView + fullScreenCover alarm takeover
    FocusView.swift          Ring, countdown, cycle dots, controls
    TimesUpView.swift        Orange alarm screen
    ProgressScreen.swift     Stats, Swift Charts, streak, empty state
    SettingsScreen.swift     Durations, cadence, alarm settings
Shared/                      Compiled into BOTH targets
  Theme.swift                Color palette
  Phase.swift                focus / shortBreak / longBreak + alarm sounds
  PomodoroAlarmMetadata.swift AlarmKit metadata (keys the Live Activity)
  AlarmControlIntents.swift  Pause/Resume/Stop LiveActivityIntents
Widget/                      PomodoroWidgets extension target
  PomodoroWidgetBundle.swift @main widget bundle
  PomodoroLiveActivity.swift Lock Screen + Dynamic Island countdown UI
```

## Design decisions

- **Wall-clock timing.** Running state stores only an `endDate`; remaining time
  is always derived. Suspension/backgrounding can never desync the timer.
- **Countdown rendering** uses `Text(timerInterval:)` — ticks system-side, no
  timer publisher.
- **Alarm-grade wake-from-lock (AlarmKit).** In **Loud** style (the default),
  starting a phase schedules a system countdown alarm via `AlarmManager`. It
  fires full-screen on the Lock Screen at full volume, breaking through Silent
  mode and Focus, and keeps ringing until stopped. Stopping from the lock
  screen banner is observed via `alarmUpdates` and dismisses the in-app
  takeover; stopping in-app calls `AlarmManager.stop`. If the user denies
  alarm permission, the engine falls back to a local notification
  (background) + synthesized in-app alarm (foreground).
- **Cowork / quiet styles.** **Headphones** and **Silent** do not schedule
  AlarmKit, so they cannot blast the speaker or break Silent/Focus. Headphones
  plays a one-shot cue only if AirPods or headphones are the current route;
  otherwise (and always in Silent) the end is haptic + the Time's up screen.
  A silent local notification still banners when the phone is locked. Switching
  Loud → quiet mid-run cancels the armed system alarm.
- **Completion UI:** a foreground `Task` sleeping until `endDate` presents the
  in-app takeover; reopened late → `checkForCompletion()` on scene activation
  (and if the alarm was already stopped from the lock screen, no re-ring).
- **Skip advances, reset restarts.** Only fully elapsed focus blocks are
  recorded to SwiftData, so stats can't be gamed by skipping.
- **Sound files.** `Resources/*.wav` are referenced by
  `AlertConfiguration.AlertSound.named(_:)` — AlarmKit plays bundled files,
  it can't synthesize at alarm time.

## Lock screen widget (Live Activity)

The running pomodoro shows on the Lock Screen and in the Dynamic Island via
AlarmKit's countdown Live Activity, rendered by the **PomodoroWidgets**
extension:

- Appears when a phase starts and disappears on reset/skip/stop — it only
  exists while a pomodoro is running or paused. No extra lifecycle code: the
  system ties the activity to the alarm we already schedule.
- Pause/resume buttons are `LiveActivityIntent`s that drive `AlarmManager`
  directly, so they work even if the app is suspended. The app mirrors
  lock-screen pauses/resumes into `TimerEngine` via `alarmUpdates` (and
  in-app pause now pauses — rather than cancels — the system alarm).
- **Chaining from the lock screen.** The ringing alert has a single button
  labeled for the next step in the series ("Focus"/"Break"). AlarmKit
  requires the alert to have a stop button, so that button IS it: the system
  stops the alarm, and its `stopIntent` hook starts the next block — whose
  fresh Live Activity takes over the lock screen. (Tapped "Break" by
  accident? Pause it from the widget.) The intent runs through
  `TimerEngine.handleLockScreenAdvance` in the app's process (launched in
  the background if needed), which treats the rung alarm as ground truth
  that the phase fully elapsed: it records the focus session and advances
  the cycle even if the engine's in-memory state went stale (e.g. a
  lock-screen resume that the process never got to observe) or the app was
  killed (cycle position restarts, as on any relaunch).
- Theme matches the app: warm near-black background, tomato-orange accent,
  cream rounded-light digits.
- Only reachable on the AlarmKit path; if alarm permission is denied, **or
  the alert style is Headphones/Silent**, there is no Live Activity (the
  widget is owned by the system alarm).
- Note: a lock-screen resume recomputes the end date app-side from the stored
  remaining time, so app and system countdowns can drift by the async-update
  latency (sub-second in practice).

## Not included yet (next steps)

- App icon

## Testing notes

- AlarmKit needs a **physical device** for the real experience (lock the
  phone, flip the silent switch — it should still ring full volume).
- Chaining regression check: focus → ring → tap "Break" → let the break
  ring → tap "Focus" → repeat a few cycles with the phone locked the whole
  time, then open Progress — every focus block should be counted.
- First timer start prompts for alarm permission
  (`NSAlarmKitUsageDescription`). Deny it to exercise the notification
  fallback path.
- Cowork check: set Silent, start a short block, confirm no speaker and no
  system alarm. Set Headphones with AirPods in, confirm a short private cue.
  Unplug before the end — haptic only, never speaker. Switch Loud → Silent
  mid-run and confirm the system alarm is gone.
