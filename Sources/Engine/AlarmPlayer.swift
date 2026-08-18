import AVFoundation

/// Fallback in-app alarm, used only when AlarmKit permission is denied.
///
/// Plays a looping, programmatically synthesized tone. Always uses the
/// `.playback` audio session category so it ignores the ring/silent switch —
/// an alarm that respects Silent mode isn't an alarm.
@MainActor
final class AlarmPlayer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var isConfigured = false

    private var routeObserver: NSObjectProtocol?

    func start(sound: AlarmSound) {
        stop()
        guard prepare(sound: sound, loops: true) else { return }
        player.play()
    }

    /// One pass of the tone, only if headphones/AirPods are the current route.
    /// Stops immediately if that private route goes away.
    func playOnce(sound: AlarmSound) {
        stop()
        guard AudioRoute.isPrivateListening else { return }
        guard prepare(sound: sound, loops: false) else { return }
        watchPrivateRoute()
        player.play()
    }

    func stop() {
        clearRouteWatch()
        if player.isPlaying { player.stop() }
        if engine.isRunning { engine.stop() }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func prepare(sound: AlarmSound, loops: Bool) -> Bool {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.allowBluetoothA2DP])
        try? session.setActive(true)

        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1),
              let buffer = Self.makeBuffer(sound: sound, format: format) else { return false }

        if !isConfigured {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            isConfigured = true
        }

        do {
            try engine.start()
        } catch {
            return false
        }
        player.volume = 1.0
        player.scheduleBuffer(buffer, at: nil, options: loops ? .loops : [])
        return true
    }

    private func watchPrivateRoute() {
        clearRouteWatch()
        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                if !AudioRoute.isPrivateListening {
                    self?.stop()
                }
            }
        }
    }

    private func clearRouteWatch() {
        if let routeObserver {
            NotificationCenter.default.removeObserver(routeObserver)
            self.routeObserver = nil
        }
    }

    // MARK: Synthesis

    private static func makeBuffer(sound: AlarmSound, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let seconds: Double = sound == .chime ? 3.0 : 2.0
        let frameCount = AVAudioFrameCount(sampleRate * seconds)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let samples = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frameCount

        var phase: Double = 0
        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / sampleRate
            let value: Double

            switch sound {
            case .siren:
                // Frequency sweeps 600–1200 Hz at 1.5 Hz — classic siren.
                let freq = 900 + 300 * sin(2 * .pi * 1.5 * t)
                phase += 2 * .pi * freq / sampleRate
                value = sin(phase) * 0.8

            case .beep:
                // 880 Hz gated on/off 4x per second.
                let gate = sin(2 * .pi * 4 * t) > 0 ? 1.0 : 0.0
                phase += 2 * .pi * 880 / sampleRate
                value = sin(phase) * gate * 0.8

            case .chime:
                // Bell-ish: fundamental + harmonics with exponential decay,
                // struck once per 1.5 s within the 3 s loop.
                let strike = t.truncatingRemainder(dividingBy: 1.5)
                let envelope = exp(-3 * strike)
                let tone = sin(2 * .pi * 660 * strike)
                    + 0.5 * sin(2 * .pi * 1320 * strike)
                    + 0.25 * sin(2 * .pi * 1980 * strike)
                value = tone * envelope * 0.4
            }

            samples[frame] = Float(value)
        }
        return buffer
    }
}
