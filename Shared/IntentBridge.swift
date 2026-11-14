import Foundation

/// The hooks the intents call. The app sets them when its process starts; in the widget process they stay nil.
@MainActor enum IntentBridge {
    static var approve: ((String?) -> Void)?
    static var deny: ((String?) -> Void)?
    static var endCall: (() -> Void)?
    static var startCall: (() -> Void)?
    static var replay: (() -> Void)?
    static var talk: (() -> Void)?
    static var hush: (() -> Void)?   // 11-14: stop Claude talking from the Lock Screen (his work goes on)
    static var heard: ((Bool) -> Void)?   // true = Yes, send it; false = Again

    /// A control can start the app process cold, so wait up to two seconds for the app to set its hooks.
    static func whenReady<Hook>(_ hook: () -> Hook?) async -> Hook? {
        for _ in 0..<20 {
            if let ready = hook() { return ready }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return hook()
    }
}

/// Thrown when the app never set the hook, so the system shows that the action did not run.
enum IntentBridgeError: Error {
    case notReady
}
