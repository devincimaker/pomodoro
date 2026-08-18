import Foundation
import Observation

@MainActor
@Observable
final class SettingsStore {
    private let defaults: UserDefaults

    var focusMinutes: Int {
        didSet { defaults.set(focusMinutes, forKey: "focusMinutes") }
    }
    var shortBreakMinutes: Int {
        didSet { defaults.set(shortBreakMinutes, forKey: "shortBreakMinutes") }
    }
    var longBreakMinutes: Int {
        didSet { defaults.set(longBreakMinutes, forKey: "longBreakMinutes") }
    }
    /// Long break after this many completed focus blocks.
    var longBreakCadence: Int {
        didSet { defaults.set(longBreakCadence, forKey: "longBreakCadence") }
    }
    var alarmSound: AlarmSound {
        didSet { defaults.set(alarmSound.rawValue, forKey: "alarmSound") }
    }
    var alertStyle: AlertStyle {
        didSet { defaults.set(alertStyle.rawValue, forKey: "alertStyle") }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let d = defaults
        focusMinutes = d.object(forKey: "focusMinutes") as? Int ?? 25
        shortBreakMinutes = d.object(forKey: "shortBreakMinutes") as? Int ?? 5
        longBreakMinutes = d.object(forKey: "longBreakMinutes") as? Int ?? 15
        longBreakCadence = d.object(forKey: "longBreakCadence") as? Int ?? 4
        alarmSound = AlarmSound(rawValue: d.string(forKey: "alarmSound") ?? "") ?? .siren
        alertStyle = AlertStyle(rawValue: d.string(forKey: "alertStyle") ?? "") ?? .loud
    }

    func duration(for phase: Phase) -> TimeInterval {
        switch phase {
        case .focus: TimeInterval(focusMinutes * 60)
        case .shortBreak: TimeInterval(shortBreakMinutes * 60)
        case .longBreak: TimeInterval(longBreakMinutes * 60)
        }
    }

    func minutes(for phase: Phase) -> Int {
        switch phase {
        case .focus: focusMinutes
        case .shortBreak: shortBreakMinutes
        case .longBreak: longBreakMinutes
        }
    }
}
