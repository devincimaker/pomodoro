import SwiftUI
import SwiftData
import Charts

struct ProgressScreen: View {
    @Binding var selectedTab: AppTab
    @Environment(TimerEngine.self) private var engine
    @Environment(SettingsStore.self) private var settings
    @Query(sort: \PomodoroSession.endedAt) private var sessions: [PomodoroSession]
    @State private var range: StatsRange = .week

    enum StatsRange: String, CaseIterable, Identifiable {
        case week = "Week"
        case month = "Month"
        var id: String { rawValue }
        var days: Int { self == .week ? 7 : 30 }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                if sessions.isEmpty {
                    emptyState
                } else {
                    Picker("Range", selection: $range) {
                        ForEach(StatsRange.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    averagesRow
                    chartCard
                    bottomRow
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .background(Color.appBackground)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Progress")
                .font(.largeTitle.bold())
                .foregroundStyle(Color.cream)
            Spacer()
            if !sessions.isEmpty {
                Text("\(sessions.count) all-time 🍅")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Empty state (mockup 3)

    private var emptyState: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                statCard(caption: "AVG / DAY", value: "0", unit: "pomodoros", dimmed: true)
                statCard(caption: "AVG / DAY", value: "0", unit: "focus minutes", dimmed: true)
            }

            Circle()
                .stroke(style: StrokeStyle(lineWidth: 2, dash: [6, 6]))
                .foregroundStyle(.white.opacity(0.2))
                .frame(width: 150, height: 150)
                .overlay {
                    Image(systemName: "clock")
                        .font(.system(size: 44))
                        .foregroundStyle(.white.opacity(0.35))
                }
                .padding(.top, 90)

            Text("No sessions yet")
                .font(.title2.bold())
                .foregroundStyle(Color.cream.opacity(0.85))
                .padding(.top, 36)

            Text("Finish your first \(settings.focusMinutes)-minute focus block and your data starts stacking up right here.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.top, 10)
                .padding(.horizontal, 24)

            Button {
                selectedTab = .focus
                if engine.isIdle { engine.start() }
            } label: {
                Text("Start focusing")
                    .font(.headline)
                    .foregroundStyle(Color.appBackground)
                    .padding(.horizontal, 36)
                    .padding(.vertical, 16)
                    .background(Capsule().fill(Color.pomodoroOrange))
                    .shadow(color: .pomodoroOrange.opacity(0.5), radius: 14)
            }
            .buttonStyle(.plain)
            .padding(.top, 32)
        }
    }

    // MARK: Stats

    private var rangeSessions: [PomodoroSession] {
        let cutoff = Calendar.current.date(
            byAdding: .day, value: -(range.days - 1),
            to: Calendar.current.startOfDay(for: .now)
        ) ?? .now
        return sessions.filter { $0.endedAt >= cutoff }
    }

    private var averagesRow: some View {
        let count = rangeSessions.count
        let minutes = rangeSessions.reduce(0) { $0 + $1.durationMinutes }
        let avgPomodoros = Double(count) / Double(range.days)
        let avgMinutes = Double(minutes) / Double(range.days)

        return HStack(spacing: 16) {
            statCard(
                caption: "AVG / DAY",
                value: String(format: "%.1f", avgPomodoros),
                unit: "pomodoros"
            )
            statCard(
                caption: "AVG / DAY",
                value: "\(Int(avgMinutes.rounded()))",
                unit: "focus minutes"
            )
        }
    }

    private func statCard(caption: String, value: String, unit: String, dimmed: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(caption)
                .font(.caption.weight(.semibold))
                .kerning(1)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .foregroundStyle(dimmed ? Color.secondary : Color.pomodoroOrange)
            Text(unit)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.cardSurface))
        .opacity(dimmed ? 0.55 : 1)
    }

    // MARK: Chart

    private struct DayCount: Identifiable {
        let date: Date
        let count: Int
        var id: Date { date }
    }

    private var dailyCounts: [DayCount] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let grouped = Dictionary(grouping: rangeSessions) {
            calendar.startOfDay(for: $0.endedAt)
        }
        return (0..<range.days).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return DayCount(date: day, count: grouped[day]?.count ?? 0)
        }
    }

    private var chartCard: some View {
        let counts = dailyCounts
        let today = Calendar.current.startOfDay(for: .now)

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(range == .week ? "This week" : "Last 30 days")
                    .font(.headline)
                    .foregroundStyle(Color.cream)
                Spacer()
                Text("\(rangeSessions.count) pomodoros")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Chart(counts) { day in
                BarMark(
                    x: .value("Day", day.date, unit: .day),
                    y: .value("Pomodoros", day.count)
                )
                .foregroundStyle(
                    day.date == today ? Color.pomodoroOrange : Color.white.opacity(0.12)
                )
                .cornerRadius(6)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: range == .week ? 1 : 7)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                        .foregroundStyle(Color.secondary)
                }
            }
            .chartYAxis(.hidden)
            .frame(height: 180)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.cardSurface))
    }

    // MARK: Bottom row

    private var bottomRow: some View {
        let totalMinutes = sessions.reduce(0) { $0 + $1.durationMinutes }
        let streak = currentStreak()

        return HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Total focus time")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(totalMinutes / 60)")
                        .font(.title.bold())
                        .foregroundStyle(Color.cream)
                    Text("h")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("\(totalMinutes % 60)")
                        .font(.title.bold())
                        .foregroundStyle(Color.cream)
                    Text("m")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color.cardSurface))

            VStack(alignment: .leading, spacing: 8) {
                Text("Current streak")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(streak)")
                        .font(.title.bold())
                        .foregroundStyle(Color.cream)
                    Text("days\(streak > 0 ? " 🔥" : "")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color.cardSurface))
        }
        .padding(.bottom, 24)
    }

    /// Consecutive days with at least one completed pomodoro, counting back
    /// from today (or yesterday, if today has none yet).
    private func currentStreak() -> Int {
        let calendar = Calendar.current
        let daysWithSessions = Set(sessions.map { calendar.startOfDay(for: $0.endedAt) })
        guard !daysWithSessions.isEmpty else { return 0 }

        var day = calendar.startOfDay(for: .now)
        if !daysWithSessions.contains(day) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day),
                  daysWithSessions.contains(yesterday) else { return 0 }
            day = yesterday
        }

        var streak = 0
        while daysWithSessions.contains(day) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return streak
    }
}
