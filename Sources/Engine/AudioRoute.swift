import AVFoundation
import UIKit

enum AudioRoute {
    /// True when the current output is private (wired headphones or Bluetooth).
    /// Speaker, receiver, and AirPlay are not private.
    static var isPrivateListening: Bool {
        AVAudioSession.sharedInstance().currentRoute.outputs.contains { port in
            switch port.portType {
            case .headphones, .bluetoothA2DP, .bluetoothLE, .bluetoothHFP:
                true
            default:
                false
            }
        }
    }
}

enum HapticCue {
    @MainActor
    static func phaseEnded() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.7)
    }
}
