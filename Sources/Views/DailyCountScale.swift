import Foundation

/// Integer Y-axis for the Progress daily-count chart.
///
/// Peak is the tallest day's count. The domain always starts at 0 and ends on
/// a tick so a 5-pomodoro day never sits between unlabeled lines.
struct DailyCountScale: Equatable, Sendable {
    let peak: Int
    let stride: Int
    let upperBound: Int

    var ticks: [Int] {
        Array(Swift.stride(from: 0, through: upperBound, by: stride))
    }

    init(peak: Int) {
        let peak = max(0, peak)
        self.peak = peak
        let stride = Self.strideLength(forPeak: peak)
        self.stride = stride
        let shown = max(peak, 1)
        let remainder = shown % stride
        self.upperBound = remainder == 0 ? shown : shown + (stride - remainder)
    }

    /// Keep 4–6 ticks for typical pomodoro days (0–8), then step up.
    static func strideLength(forPeak peak: Int) -> Int {
        switch max(peak, 1) {
        case 1...4: 1
        case 5...10: 2
        case 11...20: 4
        default: 5
        }
    }
}
