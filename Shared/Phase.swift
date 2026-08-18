import Foundation

enum Phase: String, Codable, Sendable, CaseIterable {
    case focus
    case shortBreak
    case longBreak

    var title: String {
        switch self {
        case .focus: "FOCUSING"
        case .shortBreak: "SHORT BREAK"
        case .longBreak: "LONG BREAK"
        }
    }

    var nextUpLabel: String {
        switch self {
        case .focus: "focus block"
        case .shortBreak: "short break"
        case .longBreak: "long break"
        }
    }
}

enum AlarmSound: String, Codable, Sendable, CaseIterable, Identifiable {
    case siren = "Siren"
    case beep = "Beep"
    case chime = "Chime"

    var id: String { rawValue }

    /// Bundled WAV used by the AlarmKit system alarm.
    var resourceName: String { "\(rawValue.lowercased()).wav" }
}

/// How the app announces the end of a phase.
///
/// Loud uses AlarmKit (speaker, Silent/Focus breakthrough, lock-screen
/// Live Activity). Headphones and Silent leave AlarmKit so a cowork
/// session cannot blast the room; they still show an app-owned Live
/// Activity on the Lock Screen.
enum AlertStyle: String, Codable, Sendable, CaseIterable, Identifiable {
    case loud
    case headphones
    case silent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .loud: "Loud"
        case .headphones: "Headphones"
        case .silent: "Silent"
        }
    }

    var systemImage: String {
        switch self {
        case .loud: "speaker.wave.3.fill"
        case .headphones: "headphones"
        case .silent: "speaker.slash.fill"
        }
    }

    var usesAlarmKit: Bool { self == .loud }
}
