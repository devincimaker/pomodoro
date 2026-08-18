import SwiftUI

struct TimesUpView: View {
    @Environment(TimerEngine.self) private var engine
    @Environment(SettingsStore.self) private var settings
    @State private var pulse = false

    private var finishedFocus: Bool { engine.finishedPhase == .focus }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            bell
                .padding(.bottom, 60)

            Text("Time's up")
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(.white)

            Text(finishedFocus ? "Focus session complete" : "Break's over")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.9))
                .padding(.top, 8)

            if finishedFocus {
                todayPill
                    .padding(.top, 28)
            }

            Spacer()

            Button {
                engine.stopAlarm()
            } label: {
                Text(settings.alertStyle == .loud ? "Stop alarm" : "Done")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color.pomodoroOrange)
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                    .background(RoundedRectangle(cornerRadius: 18).fill(.white))
            }
            .buttonStyle(.plain)

            if settings.alertStyle == .loud {
                Text("Alarm keeps ringing at full volume until you tap")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.top, 14)
                    .padding(.bottom, 8)
            } else {
                Color.clear.frame(height: 22)
            }
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.96, green: 0.46, blue: 0.33),
                    Color(red: 0.91, green: 0.38, blue: 0.26),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .onAppear { pulse = true }
        .interactiveDismissDisabled()
    }

    private var bell: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.25), lineWidth: 1.5)
                .frame(width: 300, height: 300)
                .scaleEffect(pulse ? 1.06 : 0.98)

            Circle()
                .stroke(.white.opacity(0.35), lineWidth: 1.5)
                .frame(width: 230, height: 230)
                .scaleEffect(pulse ? 1.04 : 0.99)

            Circle()
                .fill(.white.opacity(0.25))
                .frame(width: 160, height: 160)

            Image(systemName: "bell.fill")
                .font(.system(size: 54))
                .foregroundStyle(.white)
                .rotationEffect(.degrees(pulse ? 8 : -8), anchor: .top)
        }
        .animation(.easeInOut(duration: 0.35).repeatForever(autoreverses: true), value: pulse)
    }

    private var todayPill: some View {
        let count = engine.sessionsCompletedToday()
        return Text("🍅 \(count) pomodoro\(count == 1 ? "" : "s") stacked today")
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Capsule().fill(.white.opacity(0.18)))
    }
}
