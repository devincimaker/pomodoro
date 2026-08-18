import WidgetKit
import SwiftUI
import ActivityKit
import AppIntents
@preconcurrency import AlarmKit

/// Lock Screen + Dynamic Island presentation for the running pomodoro.
///
/// AlarmKit owns the Live Activity lifecycle: it appears when a countdown
/// alarm is scheduled and disappears when the alarm is cancelled or stopped —
/// which is exactly "only visible while a pomodoro is running". This widget
/// only supplies the UI for the countdown / paused states (the full-screen
/// ringing alert stays system-rendered).
struct PomodoroLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<PomodoroAlarmMetadata>.self) { context in
            LockScreenView(context: context)
                .activityBackgroundTint(Color.appBackground.opacity(0.96))
                .activitySystemActionForegroundColor(Color.pomodoroOrange)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    PhaseLabel(phase: phase(of: context))
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    AlarmControls(state: context.state, phase: phase(of: context), compact: true)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        CountdownDigits(mode: context.state.mode)
                            .font(.system(size: 40, weight: .light, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Color.cream)
                        SegmentProgress(mode: context.state.mode)
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: compactIcon(for: context.state.mode))
                    .foregroundStyle(Color.pomodoroOrange)
            } compactTrailing: {
                CompactCountdown(mode: context.state.mode)
            } minimal: {
                Image(systemName: compactIcon(for: context.state.mode))
                    .foregroundStyle(Color.pomodoroOrange)
            }
            .keylineTint(Color.pomodoroOrange)
        }
    }

    private func phase(of context: ActivityViewContext<AlarmAttributes<PomodoroAlarmMetadata>>) -> Phase {
        context.attributes.metadata?.phase ?? .focus
    }

    private func compactIcon(for mode: AlarmPresentationState.Mode) -> String {
        if case .paused = mode { return "pause.fill" }
        return "timer"
    }
}

// MARK: - Lock Screen

private struct LockScreenView: View {
    let context: ActivityViewContext<AlarmAttributes<PomodoroAlarmMetadata>>

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    PhaseLabel(phase: context.attributes.metadata?.phase ?? .focus)
                    CountdownDigits(mode: context.state.mode)
                        .font(.system(size: 44, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.cream)
                }
                Spacer(minLength: 12)
                AlarmControls(state: context.state, phase: context.attributes.metadata?.phase ?? .focus, compact: false)
            }
            SegmentProgress(mode: context.state.mode)
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
    let mode: AlarmPresentationState.Mode

    var body: some View {
        switch mode {
        case .countdown(let countdown):
            Text(
                timerInterval: Self.range(for: countdown),
                countsDown: true,
                showsHours: false
            )
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            // fireDate only changes on pause/resume. Pinning identity
            // stops AlarmKit refreshes from remounting the timer (skipped seconds).
            .id(countdown.fireDate)
        case .paused(let paused):
            Text(Self.formatted(max(0, paused.totalCountdownDuration - paused.previouslyElapsedDuration)))
        case .alert:
            Text("0:00")
        @unknown default:
            Text("--:--")
        }
    }

    /// Full phase window ending at the alarm fire date. `startDate` can drift
    /// on system refreshes; this range stays put so the timer does not skip.
    static func range(for countdown: AlarmPresentationState.Mode.Countdown) -> ClosedRange<Date> {
        countdown.fireDate.addingTimeInterval(-countdown.totalCountdownDuration)...countdown.fireDate
    }

    static func formatted(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Narrow countdown for the compact Dynamic Island slot.
private struct CompactCountdown: View {
    let mode: AlarmPresentationState.Mode

    var body: some View {
        switch mode {
        case .countdown(let countdown):
            Text(
                timerInterval: CountdownDigits.range(for: countdown),
                countsDown: true,
                showsHours: false
            )
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .frame(width: 58, alignment: .trailing)
                .foregroundStyle(Color.cream)
                .id(countdown.fireDate)
        case .paused(let paused):
            Text(CountdownDigits.formatted(max(0, paused.totalCountdownDuration - paused.previouslyElapsedDuration)))
                .monospacedDigit()
                .foregroundStyle(Color.cream.opacity(0.6))
        default:
            Image(systemName: "bell.fill")
                .foregroundStyle(Color.pomodoroOrange)
        }
    }
}

/// Thin progress bar through the current running segment — the linear
/// counterpart of the app's progress ring.
private struct SegmentProgress: View {
    let mode: AlarmPresentationState.Mode

    var body: some View {
        Group {
            switch mode {
            case .countdown(let countdown):
                ProgressView(
                    timerInterval: countdown.fireDate.addingTimeInterval(-countdown.totalCountdownDuration)...countdown.fireDate,
                    countsDown: false,
                    label: {},
                    currentValueLabel: {}
                )
            case .paused(let paused):
                ProgressView(
                    value: min(max(paused.previouslyElapsedDuration, 0), paused.totalCountdownDuration),
                    total: max(paused.totalCountdownDuration, 1)
                )
            default:
                ProgressView(value: 1, total: 1)
            }
        }
        .progressViewStyle(.linear)
        .tint(Color.pomodoroOrange)
        .labelsHidden()
        .scaleEffect(y: 0.8)
    }
}

/// Pause / resume buttons while counting down, and stop / start-next while
/// ringing — all LiveActivityIntents that drive the real AlarmKit alarm (the
/// app syncs itself via `alarmUpdates`, and the chaining intents route
/// through TimerEngine in the app's process).
private struct AlarmControls: View {
    let state: AlarmPresentationState
    let phase: Phase
    let compact: Bool

    private var primarySize: CGFloat { compact ? 44 : 54 }

    var body: some View {
        switch state.mode {
        case .countdown:
            HStack(spacing: compact ? 10 : 14) {
                stopButton
                primaryButton(
                    intent: PausePomodoroIntent(alarmID: state.alarmID),
                    systemImage: "pause.fill"
                )
            }
        case .paused:
            HStack(spacing: compact ? 10 : 14) {
                stopButton
                primaryButton(
                    intent: ResumePomodoroIntent(alarmID: state.alarmID),
                    systemImage: "play.fill"
                )
            }
        case .alert:
            // Ringing: one button — jump straight into the next phase
            // (mirrors the system alert's single "Focus"/"Break" button).
            primaryButton(
                intent: StartNextPhaseIntent(finishedPhase: phase, alarmID: state.alarmID),
                systemImage: "play.fill"
            )
        @unknown default:
            EmptyView()
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
        return Button(intent: StopPomodoroIntent(alarmID: state.alarmID)) {
            Image(systemName: "xmark")
                .font(.system(size: compact ? 13 : 15, weight: .bold))
                .foregroundStyle(Color.cream.opacity(0.9))
                .frame(width: size, height: size)
                .background(Circle().fill(Color.white.opacity(0.14)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Stop timer")
    }
}
