import WidgetKit
import SwiftUI
import ActivityKit
import AppIntents
@preconcurrency import AlarmKit

/// Lock Screen + Dynamic Island presentation for the running pomodoro.
///
/// Two configurations share the same chrome:
/// - AlarmKit's countdown activity (Loud)
/// - The app-owned `PomodoroActivityAttributes` activity (Headphones / Silent,
///   and Loud when alarm permission is denied)
struct PomodoroLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<PomodoroAlarmMetadata>.self) { context in
            LockScreenBanner(
                phase: context.attributes.metadata?.phase ?? .focus,
                mode: lockScreenMode(of: context.state.mode),
                controls: .alarmKit(alarmID: context.state.alarmID)
            )
            .activityBackgroundTint(Color.appBackground.opacity(0.96))
            .activitySystemActionForegroundColor(Color.pomodoroOrange)
        } dynamicIsland: { context in
            island(
                phase: phase(of: context),
                mode: lockScreenMode(of: context.state.mode),
                controls: .alarmKit(alarmID: context.state.alarmID)
            )
        }
    }

    private func phase(of context: ActivityViewContext<AlarmAttributes<PomodoroAlarmMetadata>>) -> Phase {
        context.attributes.metadata?.phase ?? .focus
    }
}

/// App-owned Live Activity used when AlarmKit is not scheduled.
struct QuietPomodoroLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PomodoroActivityAttributes.self) { context in
            LockScreenBanner(
                phase: context.state.phase,
                mode: context.state.lockScreenMode,
                controls: .quiet
            )
            .activityBackgroundTint(Color.appBackground.opacity(0.96))
            .activitySystemActionForegroundColor(Color.pomodoroOrange)
        } dynamicIsland: { context in
            island(
                phase: context.state.phase,
                mode: context.state.lockScreenMode,
                controls: .quiet
            )
        }
    }
}

private func island(
    phase: Phase,
    mode: PomodoroLockScreenMode,
    controls: LockScreenControlKind
) -> DynamicIsland {
    DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
            PhaseLabel(phase: phase)
                .padding(.leading, 4)
        }
        DynamicIslandExpandedRegion(.trailing) {
            AlarmControls(mode: mode, phase: phase, compact: true, controls: controls)
                .padding(.trailing, 4)
        }
        DynamicIslandExpandedRegion(.bottom) {
            VStack(spacing: 8) {
                CountdownDigits(mode: mode)
                    .font(.system(size: 40, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.cream)
                SegmentProgress(mode: mode)
            }
            .padding(.horizontal, 4)
        }
    } compactLeading: {
        Image(systemName: compactIcon(for: mode))
            .foregroundStyle(Color.pomodoroOrange)
    } compactTrailing: {
        CompactCountdown(mode: mode)
    } minimal: {
        Image(systemName: compactIcon(for: mode))
            .foregroundStyle(Color.pomodoroOrange)
    }
    .keylineTint(Color.pomodoroOrange)
}

private func compactIcon(for mode: PomodoroLockScreenMode) -> String {
    if case .paused = mode { return "pause.fill" }
    return "timer"
}

private func lockScreenMode(of mode: AlarmPresentationState.Mode) -> PomodoroLockScreenMode {
    switch mode {
    case .countdown(let countdown):
        .countdown(endDate: countdown.fireDate, totalDuration: countdown.totalCountdownDuration)
    case .paused(let paused):
        .paused(
            remaining: max(0, paused.totalCountdownDuration - paused.previouslyElapsedDuration),
            totalDuration: paused.totalCountdownDuration
        )
    case .alert:
        .finished
    @unknown default:
        .finished
    }
}

// MARK: - Lock Screen

private enum LockScreenControlKind {
    case alarmKit(alarmID: UUID)
    case quiet
}

private struct LockScreenBanner: View {
    let phase: Phase
    let mode: PomodoroLockScreenMode
    let controls: LockScreenControlKind

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    PhaseLabel(phase: phase)
                    CountdownDigits(mode: mode)
                        .font(.system(size: 44, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.cream)
                }
                Spacer(minLength: 12)
                AlarmControls(mode: mode, phase: phase, compact: false, controls: controls)
            }
            SegmentProgress(mode: mode)
        }
        .padding(16)
    }
}

// MARK: - Pieces

/// "FOCUS" / "BREAK" eyebrow, same treatment as FocusView's header.
private struct PhaseLabel: View {
    let phase: Phase

    var body: some View {
        Text(phase == .focus ? "FOCUS" : "BREAK")
            .font(.footnote.weight(.bold))
            .kerning(2)
            .foregroundStyle(Color.pomodoroOrange)
    }
}

/// Big countdown digits. While counting down the text ticks system-side
/// (no timeline needed); while paused it shows the frozen remaining time.
private struct CountdownDigits: View {
    let mode: PomodoroLockScreenMode

    var body: some View {
        switch mode {
        case .countdown(let endDate, let totalDuration):
            Text(
                timerInterval: Self.range(endDate: endDate, totalDuration: totalDuration),
                countsDown: true,
                showsHours: false
            )
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .id(endDate)
        case .paused(let remaining, _):
            Text(Self.formatted(max(0, remaining)))
        case .finished:
            Text("0:00")
        }
    }

    static func range(endDate: Date, totalDuration: TimeInterval) -> ClosedRange<Date> {
        endDate.addingTimeInterval(-totalDuration)...endDate
    }

    static func formatted(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Narrow countdown for the compact Dynamic Island slot.
private struct CompactCountdown: View {
    let mode: PomodoroLockScreenMode

    var body: some View {
        switch mode {
        case .countdown(let endDate, let totalDuration):
            Text(
                timerInterval: CountdownDigits.range(endDate: endDate, totalDuration: totalDuration),
                countsDown: true,
                showsHours: false
            )
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .frame(width: 58, alignment: .trailing)
                .foregroundStyle(Color.cream)
                .id(endDate)
        case .paused(let remaining, _):
            Text(CountdownDigits.formatted(max(0, remaining)))
                .monospacedDigit()
                .foregroundStyle(Color.cream.opacity(0.6))
        case .finished:
            Image(systemName: "bell.fill")
                .foregroundStyle(Color.pomodoroOrange)
        }
    }
}

/// Thin progress bar through the current running segment — the linear
/// counterpart of the app's progress ring.
private struct SegmentProgress: View {
    let mode: PomodoroLockScreenMode

    var body: some View {
        Group {
            switch mode {
            case .countdown(let endDate, let totalDuration):
                ProgressView(
                    timerInterval: endDate.addingTimeInterval(-totalDuration)...endDate,
                    countsDown: false,
                    label: {},
                    currentValueLabel: {}
                )
            case .paused(let remaining, let totalDuration):
                let elapsed = max(0, totalDuration - remaining)
                ProgressView(
                    value: min(elapsed, totalDuration),
                    total: max(totalDuration, 1)
                )
            case .finished:
                ProgressView(value: 1, total: 1)
            }
        }
        .progressViewStyle(.linear)
        .tint(Color.pomodoroOrange)
        .labelsHidden()
        .scaleEffect(y: 0.8)
    }
}

/// Pause / resume / stop. AlarmKit buttons drive `AlarmManager`; quiet
/// buttons drive `TimerEngine` so there is no system alarm to talk to.
private struct AlarmControls: View {
    let mode: PomodoroLockScreenMode
    let phase: Phase
    let compact: Bool
    let controls: LockScreenControlKind

    private var primarySize: CGFloat { compact ? 44 : 54 }

    var body: some View {
        switch mode {
        case .countdown:
            HStack(spacing: compact ? 10 : 14) {
                stopButton
                pauseButton
            }
        case .paused:
            HStack(spacing: compact ? 10 : 14) {
                stopButton
                resumeButton
            }
        case .finished:
            // Ringing AlarmKit alert: jump into the next phase. Quiet styles
            // never reach this — they hide the activity at completion.
            if case .alarmKit(let alarmID) = controls {
                primaryButton(
                    intent: StartNextPhaseIntent(finishedPhase: phase, alarmID: alarmID),
                    systemImage: "play.fill"
                )
            }
        }
    }

    @ViewBuilder
    private var pauseButton: some View {
        switch controls {
        case .alarmKit(let alarmID):
            primaryButton(intent: PausePomodoroIntent(alarmID: alarmID), systemImage: "pause.fill")
        case .quiet:
            primaryButton(intent: PauseQuietPomodoroIntent(), systemImage: "pause.fill")
        }
    }

    @ViewBuilder
    private var resumeButton: some View {
        switch controls {
        case .alarmKit(let alarmID):
            primaryButton(intent: ResumePomodoroIntent(alarmID: alarmID), systemImage: "play.fill")
        case .quiet:
            primaryButton(intent: ResumeQuietPomodoroIntent(), systemImage: "play.fill")
        }
    }

    /// Filled orange circle, mirroring the app's main play/pause button.
    private func primaryButton(intent: some LiveActivityIntent, systemImage: String) -> some View {
        Button(intent: intent) {
            Image(systemName: systemImage)
                .font(.system(size: compact ? 16 : 20, weight: .bold))
                .foregroundStyle(Color.appBackground)
                .frame(width: primarySize, height: primarySize)
                .background(Circle().fill(Color.pomodoroOrange))
        }
        .buttonStyle(.plain)
    }

    private var stopButton: some View {
        let size = compact ? 36.0 : 44.0
        return Group {
            switch controls {
            case .alarmKit(let alarmID):
                Button(intent: StopPomodoroIntent(alarmID: alarmID)) {
                    stopGlyph(size: size)
                }
            case .quiet:
                Button(intent: StopQuietPomodoroIntent()) {
                    stopGlyph(size: size)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Stop timer")
    }

    private func stopGlyph(size: CGFloat) -> some View {
        Image(systemName: "xmark")
            .font(.system(size: compact ? 13 : 15, weight: .bold))
            .foregroundStyle(Color.cream.opacity(0.9))
            .frame(width: size, height: size)
            .background(Circle().fill(Color.white.opacity(0.14)))
    }
}
