import AppIntents

// These compile into the app and the widget extension. The system runs them in the app's process,
// because they are Live Activity or audio recording intents.

struct ApproveIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Approve"
    static let supportedModes: IntentModes = .background
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @MainActor func perform() async throws -> some IntentResult {
        guard let run = await IntentBridge.whenReady({ IntentBridge.approve }) else { throw IntentBridgeError.notReady }
        run(nil)
        return .result()
    }
}

struct DenyIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Deny"
    static let supportedModes: IntentModes = .background

    @MainActor func perform() async throws -> some IntentResult {
        guard let run = await IntentBridge.whenReady({ IntentBridge.deny }) else { throw IntentBridgeError.notReady }
        run(nil)
        return .result()
    }
}

/// A short ready-made answer. It denies unless `allow` is true, so a preset can never approve by accident.
struct PresetReplyIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Send a Short Reply"
    static let supportedModes: IntentModes = .background
    static let isDiscoverable: Bool = false

    @Parameter(title: "Message") var text: String
    @Parameter(title: "Allow", default: false) var allow: Bool

    init() {}

    init(text: String, allow: Bool = false) {
        self.text = text
        self.allow = allow
    }

    @MainActor func perform() async throws -> some IntentResult {
        let message = text
        if allow {
            guard let run = await IntentBridge.whenReady({ IntentBridge.approve }) else { throw IntentBridgeError.notReady }
            run(message)
        } else {
            guard let run = await IntentBridge.whenReady({ IntentBridge.deny }) else { throw IntentBridgeError.notReady }
            run(message)
        }
        return .result()
    }
}

struct EndCallIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "End the Call"
    static let supportedModes: IntentModes = .background

    @MainActor func perform() async throws -> some IntentResult {
        guard let run = await IntentBridge.whenReady({ IntentBridge.endCall }) else { throw IntentBridgeError.notReady }
        run()
        return .result()
    }
}

struct ReplayIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Say It Again"
    static let supportedModes: IntentModes = .background

    @MainActor func perform() async throws -> some IntentResult {
        guard let run = await IntentBridge.whenReady({ IntentBridge.replay }) else { throw IntentBridgeError.notReady }
        run()
        return .result()
    }
}

struct TalkIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Talk"
    static let supportedModes: IntentModes = .background

    @MainActor func perform() async throws -> some IntentResult {
        guard let run = await IntentBridge.whenReady({ IntentBridge.talk }) else { throw IntentBridgeError.notReady }
        run()
        return .result()
    }
}

/// Starts the microphone from a control or a shortcut. The app must start its Live Activity in the same step, or the system stops the recording.
struct StartCallIntent: AudioRecordingIntent {
    static let title: LocalizedStringResource = "Start a Call"
    static let supportedModes: IntentModes = .background

    @MainActor func perform() async throws -> some IntentResult {
        guard let run = await IntentBridge.whenReady({ IntentBridge.startCall }) else { throw IntentBridgeError.notReady }
        run()
        return .result()
    }
}
