import SwiftUI
import UIKit

struct FocusView: View {
    @Environment(TimerEngine.self) private var engine
    @Environment(SettingsStore.self) private var settings
    @State private var isScrubbing = false
    @State private var lastSeekProgress: Double?

    var body: some View {
        VStack(spacing: 0) {
            header
            Spacer()
            timerRing
            Spacer()
            cycleDots
                .padding(.bottom, 12)
            Text(cycleHint)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            controls
            Text("Next up · \(settings.minutes(for: engine.nextPhase)) min \(engine.nextPhase.nextUpLabel)")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 20)
                .padding(.bottom, 8)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Text(engine.phase == .focus ? "FOCUS" : "BREAK")
                .font(.footnote.weight(.bold))
                .kerning(2)
                .foregroundStyle(Color.pomodoroOrange)
            Spacer()
            if engine.phase == .focus {
                Text("Pomodoro \(engine.cyclePosition) of \(settings.longBreakCadence)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            alertStyleMenu
        }
        .padding(.top, 8)
    }

    private var alertStyleMenu: some View {
        @Bindable var settings = settings
        return Menu {
            Picker("Alert style", selection: $settings.alertStyle) {
                ForEach(AlertStyle.allCases) { style in
                    Label(style.title, systemImage: style.systemImage)
                        .tag(style)
                }
            }
        } label: {
            Image(systemName: settings.alertStyle.systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.cream.opacity(0.85))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Alert style, \(settings.alertStyle.title)")
    }

    // MARK: Ring + countdown

    private var timerRing: some View {
        GeometryReader { geo in
            ZStack {
                // Only the ring needs a 0.5s tick. Rebuilding the digit Text
                // on that cadence remounts the system timer and skips seconds.
                TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                    ZStack {
                        Circle()
                            .stroke(Color.ringTrack, style: StrokeStyle(lineWidth: 14, lineCap: .round))

                        Circle()
                            .trim(from: 0, to: engine.progress)
                            .stroke(
                                Color.pomodoroOrange,
                                style: StrokeStyle(lineWidth: 14, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .shadow(color: .pomodoroOrange.opacity(0.6), radius: 12)
                            .animation(isScrubbing ? nil : .linear(duration: 0.5), value: engine.progress)
                    }
                }

                VStack(spacing: 10) {
                    countdownText
                        .font(.system(size: 64, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.cream)

                    Text(engine.phase.title)
                        .font(.footnote.weight(.semibold))
                        .kerning(3)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
            .gesture(seekGesture(in: geo.size))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Timer")
            .accessibilityValue(formatted(engine.remaining))
            .accessibilityHint("Drag around the ring to adjust remaining time")
            .accessibilityAdjustableAction { direction in
                let step: TimeInterval = 60
                switch direction {
                case .increment:
                    engine.seek(toRemaining: engine.remaining + step)
                case .decrement:
                    engine.seek(toRemaining: engine.remaining - step)
                @unknown default:
                    break
                }
            }
        }
        .frame(width: 290, height: 290)
    }

    private func seekGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard let raw = RingSeek.progress(at: value.location, in: size) else { return }
                let progress = RingSeek.clampedProgress(raw, previous: lastSeekProgress)
                if !isScrubbing {
                    isScrubbing = true
                    UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.45)
                }
                lastSeekProgress = progress
                engine.seek(progress: progress, rearm: false)
            }
            .onEnded { value in
                guard isScrubbing else { return }
                if let raw = RingSeek.progress(at: value.location, in: size) {
                    engine.seek(
                        progress: RingSeek.clampedProgress(raw, previous: lastSeekProgress),
                        rearm: true
                    )
                } else if let lastSeekProgress {
                    engine.seek(progress: lastSeekProgress, rearm: true)
                }
                isScrubbing = false
                lastSeekProgress = nil
            }
    }

    @ViewBuilder
    private var countdownText: some View {
        if isScrubbing {
            Text(formatted(engine.remaining))
        } else if let endDate = engine.endDate, endDate > .now {
            let start = endDate.addingTimeInterval(-settings.duration(for: engine.phase))
            Text(timerInterval: start...endDate, countsDown: true, showsHours: false)
                .id(endDate)
        } else if engine.hasStaleEndDate {
            // AlarmKit is still counting after a lock-screen pause/resume we
            // haven't synced a fire date for yet. Don't flash 0:00.
            Text("--:--")
        } else {
            Text(formatted(engine.remaining))
        }
    }

    private func formatted(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: Cycle dots

    private var cycleDots: some View {
        HStack(spacing: 14) {
            ForEach(0..<settings.longBreakCadence, id: \.self) { index in
                Circle()
                    .fill(dotColor(for: index))
                    .frame(width: index == engine.completedInCycle ? 12 : 9,
                           height: index == engine.completedInCycle ? 12 : 9)
            }
        }
    }

    private func dotColor(for index: Int) -> Color {
        if index < engine.completedInCycle {
            return .pomodoroOrange.opacity(0.55)
        } else if index == engine.completedInCycle {
            return .pomodoroOrange
        } else {
            return .white.opacity(0.18)
        }
    }

    private var cycleHint: String {
        let left = engine.focusBlocksUntilLongBreak
        if engine.phase == .longBreak || left == 0 {
            return "Long break time"
        }
        return left == 1 ? "1 more until a long break" : "\(left) more until a long break"
    }

    // MARK: Controls

    private var controls: some View {
        HStack(spacing: 36) {
            circleButton(systemImage: "arrow.counterclockwise", size: 58) {
                engine.reset()
            }

            Button {
                engine.togglePlayPause()
            } label: {
                Image(systemName: engine.isRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(Color.appBackground)
                    .frame(width: 88, height: 88)
                    .background(Circle().fill(Color.pomodoroOrange))
                    .shadow(color: .pomodoroOrange.opacity(0.5), radius: 16)
            }
            .buttonStyle(.plain)

            circleButton(systemImage: "forward.end.fill", size: 58) {
                engine.skip()
            }
        }
    }

    private func circleButton(
        systemImage: String,
        size: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.cream.opacity(0.85))
                .frame(width: size, height: size)
                .background(Circle().fill(Color.cardSurface))
        }
        .buttonStyle(.plain)
    }
}
