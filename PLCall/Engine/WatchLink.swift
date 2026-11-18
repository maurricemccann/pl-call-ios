import Foundation
import WatchConnectivity

/// The wrist: sends the call's state to the watch app and takes its commands. It does nothing when no watch app is installed.
final class WatchLink: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = WatchLink()

    func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(state: String, line: String, ask: String?, canAnswer: Bool, push: Bool, inCall: Bool,
              tap: Bool = false, options: [String] = [], more: Int = 0, longQuestion: Bool = false, askID: String? = nil) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        var context: [String: Any] = ["state": state, "line": line, "canAnswer": canAnswer, "push": push, "inCall": inCall,
                                      "tap": tap, "options": options, "more": more, "long": longQuestion]
        if let ask { context["ask"] = ask }
        if let askID { context["askID"] = askID }
        try? session.updateApplicationContext(context)   // kept by the system for when the watch app opens
        if session.isReachable { session.sendMessage(context, replyHandler: nil, errorHandler: nil) }   // live while it is open
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {}

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        took(message)
    }

    /// A command the watch queued while the iPhone was out of reach arrives here, whenever the two meet again.
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        took(userInfo)
    }

    private func took(_ message: [String: Any]) {
        let command = message["cmd"] as? String ?? ""
        let text = message["text"] as? String
        let requestID = message["rid"] as? String
        Task { @MainActor in CallModel.shared.watchCommand(command, text: text, requestID: requestID) }
    }
}
