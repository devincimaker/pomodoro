import CoreGraphics
import Foundation

/// Maps a point on the focus ring to phase progress and remaining time.
///
/// The ring starts at 12 o'clock and fills clockwise. Progress `0` is a
/// full remaining phase; progress `1` is almost done (clamped to
/// `remainingFloor` so a scrub cannot complete the block).
enum RingSeek {
    /// Smallest remaining a scrub can leave, in seconds. Stops a drag to
    /// 12 o'clock from completing the block and recording a session.
    static let remainingFloor: TimeInterval = 2

    /// Inner / outer radius as a fraction of half the view's shortest side.
    /// Keeps the digits in the middle from starting a seek.
    static let innerRadiusFraction: CGFloat = 0.70
    static let outerRadiusFraction: CGFloat = 1.06

    /// Progress around the ring, or `nil` when the point is in the dead zone.
    static func progress(at point: CGPoint, in size: CGSize) -> Double? {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let dx = point.x - center.x
        let dy = point.y - center.y
        let radius = hypot(dx, dy)
        let half = min(size.width, size.height) / 2
        guard half > 0 else { return nil }
        let inner = half * innerRadiusFraction
        let outer = half * outerRadiusFraction
        guard radius >= inner, radius <= outer else { return nil }

        // 0 at 12 o'clock, increasing clockwise.
        var angle = atan2(dx, -dy)
        if angle < 0 { angle += 2 * .pi }
        return angle / (2 * .pi)
    }

    /// Stops a drag across 12 o'clock from wrapping full → empty.
    static func clampedProgress(_ raw: Double, previous: Double?) -> Double {
        let progress = min(1, max(0, raw))
        guard let previous else { return progress }
        if previous > 0.75, progress < 0.25 { return 1 }
        if previous < 0.25, progress > 0.75 { return 0 }
        return progress
    }

    static func remaining(progress: Double, total: TimeInterval) -> TimeInterval {
        clampedRemaining((1 - min(1, max(0, progress))) * total, total: total)
    }

    static func clampedRemaining(_ raw: TimeInterval, total: TimeInterval) -> TimeInterval {
        let ceiling = max(total, remainingFloor)
        return min(ceiling, max(remainingFloor, raw))
    }
}
