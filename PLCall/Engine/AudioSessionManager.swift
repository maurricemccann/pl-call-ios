import AVFoundation

/// The one audio session setup for the call. For a CallKit call the system activates the session
/// (CXProviderDelegate didActivate); `activate()` is only for the voice outside a call and the no-CallKit fallback.
enum AudioSessionManager {
    enum Change: Sendable { case interrupted, resumed, routeChanged, engineReset }

    /// The session for one listening mode (`AudioPlan` holds the choices and is tested on its own).
    /// Auto is the call: voiceChat, no other media. Push to talk is no phone call: the session is taken for a turn, so his music pauses,
    /// and `deactivate()` lets it resume. Tap is playback only: music dips while Claude speaks, `deactivate()` after each utterance
    /// brings it back to full, and it never records.
    /// No `.bluetoothHighQualityRecording` (his report 11-13, AirPods dead on calls): Apple allows it only in the default mode, and the mic's
    /// voice processing moves the session to voiceChat, where AirPods get no audio at all (same failure: livekit client-sdk-react-native #467).
    static func configure(_ plan: AudioPlan = AudioPlan.plan(for: .handsFree)) throws {
        var options: AVAudioSession.CategoryOptions = []
        if plan.mixWithOthers { options.insert(.mixWithOthers) }
        if plan.duckOthers { options.insert(.duckOthers) }
        if plan.category == .playAndRecord {   // these three are valid only with a record category: a playback session would refuse them
            options.insert(.allowBluetoothA2DP)
            options.insert(.defaultToSpeaker)
            if plan.bluetoothHFP { options.insert(.allowBluetoothHFP) }
        }
        try AVAudioSession.sharedInstance().setCategory(plan.category == .playback ? .playback : .playAndRecord,
                                                        mode: plan.mode == .voiceChat ? .voiceChat : .default, options: options)
    }

    static func activate(_ plan: AudioPlan = AudioPlan.plan(for: .handsFree)) throws {
        try configure(plan)
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
