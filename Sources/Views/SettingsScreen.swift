import SwiftUI

struct SettingsScreen: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text("Settings")
                    .font(.largeTitle.bold())
                    .foregroundStyle(Color.cream)

                section("DURATIONS") {
                    stepperRow(
                        dot: .pomodoroOrange,
                        label: "Focus block",
                        value: $settings.focusMinutes,
                        range: 5...90,
                        step: 5,
                        format: { "\($0) min" }
                    )
                    divider
                    stepperRow(
                        dot: .green,
                        label: "Short break",
                        value: $settings.shortBreakMinutes,
                        range: 1...30,
                        step: 1,
                        format: { "\($0) min" }
                    )
                    divider
                    stepperRow(
                        dot: .blue,
                        label: "Long break",
                        value: $settings.longBreakMinutes,
                        range: 5...60,
                        step: 5,
                        format: { "\($0) min" }
                    )
                }

                section("LONG BREAK CADENCE") {
                    stepperRow(
                        dot: nil,
                        label: "Long break after",
                        value: $settings.longBreakCadence,
                        range: 2...8,
                        step: 1,
                        format: { "\($0) 🍅" }
                    )
                }

                section("ALERT STYLE") {
                    HStack {
                        Text("Style")
                            .foregroundStyle(Color.cream)
                        Spacer()
                        Picker("Style", selection: $settings.alertStyle) {
                            ForEach(AlertStyle.allCases) { style in
                                Text(style.title).tag(style)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(.secondary)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)

                    divider

                    HStack {
                        Text("Sound")
                            .foregroundStyle(Color.cream)
                        Spacer()
                        Picker("Sound", selection: $settings.alarmSound) {
                            ForEach(AlarmSound.allCases) { sound in
                                Text(sound.rawValue).tag(sound)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(.secondary)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                }

                Label {
                    Text(alertStyleCaption)
                } icon: {
                    Image(systemName: settings.alertStyle.systemImage)
                        .foregroundStyle(Color.pomodoroOrange)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(Color.appBackground)
    }

    // MARK: Building blocks

    private var alertStyleCaption: String {
        switch settings.alertStyle {
        case .loud:
            "Alarms ring at full volume through the Lock Screen, Silent mode, and Focus until you stop them."
        case .headphones:
            "Ends with a short cue on AirPods or headphones. If none are connected, you get a haptic and the Time's up screen — no speaker. The countdown still shows on the Lock Screen."
        case .silent:
            "Ends with a haptic and the Time's up screen. No sound and no lock-screen alarm, but the countdown still shows on the Lock Screen."
        }
    }

    private var divider: some View {
        Divider().overlay(Color.white.opacity(0.06)).padding(.leading, 18)
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .kerning(1.5)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                content()
            }
            .background(RoundedRectangle(cornerRadius: 18).fill(Color.cardSurface))
        }
    }

    private func stepperRow(
        dot: Color?,
        label: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        step: Int,
        format: @escaping (Int) -> String
    ) -> some View {
        HStack(spacing: 12) {
            if let dot {
                Circle().fill(dot).frame(width: 9, height: 9)
            }
            Text(label)
                .foregroundStyle(Color.cream)

            Spacer()

            stepButton("minus") {
                value.wrappedValue = max(range.lowerBound, value.wrappedValue - step)
            }
            .disabled(value.wrappedValue <= range.lowerBound)

            Text(format(value.wrappedValue))
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.cream)
                .frame(minWidth: 62)
                .contentTransition(.numericText())
                .animation(.snappy, value: value.wrappedValue)

            stepButton("plus") {
                value.wrappedValue = min(range.upperBound, value.wrappedValue + step)
            }
            .disabled(value.wrappedValue >= range.upperBound)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private func stepButton(_ systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.cream.opacity(0.85))
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.07)))
        }
        .buttonStyle(.plain)
    }
}
