import AVFoundation

/// The one audio session setup for the call. For a CallKit call the system activates the session
/// (CXProviderDelegate didActivate); `activate()` is only for the voice outside a call and the no-CallKit fallback.
enum AudioSessionManager {
    enum Change: Sendable { case interrupted, resumed, routeChanged, engineReset }

    /// `music`: no phone-style call. Other audio keeps playing, headphones stay in full quality (A2DP).
    /// `.bluetoothHighQualityRecording` (iOS 26) lets AirPods that support it record in full quality too.
    static func configure(music: Bool = false) throws {
        if music {
            try AVAudioSession.sharedInstance().setCategory(
                .playAndRecord, mode: .default,
                options: [.mixWithOthers, .allowBluetoothA2DP, .bluetoothHighQualityRecording, .defaultToSpeaker])
        } else {
            try AVAudioSession.sharedInstance().setCategory(
                .playAndRecord, mode: .voiceChat,
                options: [.allowBluetoothHFP, .allowBluetoothA2DP, .defaultToSpeaker])
        }
    }

    static func activate(music: Bool = false) throws {
        try configure(music: music)
        try AVAudioSession.sharedInstance().setActive(true)
    }

    static func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    static func micAllowed() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    /// Interruptions arrive on the main thread and route changes on a secondary one, so the handler must be thread-free.
    static func observe(_ handler: @escaping @Sendable (Change) -> Void) {
        let center = NotificationCenter.default
        _ = center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: nil) { note in
            let began = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == 1   // 1 = began, 0 = ended
            handler(began ? .interrupted : .resumed)
        }
        _ = center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: nil) { note in
            let raw = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) ?? 0
            let reason = AVAudioSession.RouteChangeReason(rawValue: raw)
            if reason == .newDeviceAvailable || reason == .oldDeviceUnavailable || reason == .override || reason == .routeConfigurationChange {
                handler(.routeChanged)   // AirPods in or out, or the audio picker moved the sound
            }
        }
        _ = center.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: nil) { _ in
            handler(.engineReset)
        }
    }
}
