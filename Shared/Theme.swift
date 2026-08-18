import SwiftUI

extension Color {
    /// Primary accent — the tomato orange from the mockups (#F26D4F-ish).
    static let pomodoroOrange = Color(red: 0.949, green: 0.427, blue: 0.310)

    /// Near-black warm background (#171310-ish).
    static let appBackground = Color(red: 0.090, green: 0.075, blue: 0.063)

    /// Slightly raised card surface.
    static let cardSurface = Color(red: 0.137, green: 0.118, blue: 0.102)

    /// Dim track behind the progress ring.
    static let ringTrack = Color.white.opacity(0.08)

    /// Warm off-white for primary text.
    static let cream = Color(red: 0.98, green: 0.96, blue: 0.93)
}
