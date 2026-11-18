import SwiftUI
import WatchConnectivity

// The wrist: the call's state, Approve and Deny (with a short message), Talk, Replay and End.
// It holds no key and never reaches the PC. Everything goes through the Call app on the iPhone.

@main
struct PLCallWatchApp: App {
    @State private var model = WatchModel()

    var body: some Scene {
        WindowGroup {
            WatchScreen(model: model)
        }
    }
}

/// What the iPhone last said about the call.
struct WatchSnapshot: Sendable {
    var state = "idle"
    var line = ""
    var ask: String?
    var canAnswer = false
    var push = false
    var inCall = false
    var tap = false
    var options: [String] = []
    var more = 0
    var askID: String?
    var longQuestion = false   // more than four options, or several may be picked: finish it on the iPhone

    init() {}

    init(_ values: [String: Any]) {
        state = values["state"] as? String ?? "idle"
        line = values["line"] as? String ?? ""
        ask = values["ask"] as? String
        canAnswer = values["canAnswer"] as? Bool ?? false
        push = values["push"] as? Bool ?? false
        inCall = values["inCall"] as? Bool ?? false
        tap = values["tap"] as? Bool ?? false
        options = values["options"] as? [String] ?? []
        more = values["more"] as? Int ?? 0
        longQuestion = values["long"] as? Bool ?? false
        askID = values["askID"] as? String
    }
}

@MainActor @Observable final class WatchModel {
    var snapshot = WatchSnapshot()
    var reachable = false
    var note: String?

    private let link = WatchSide()

    init() {
        link.onSnapshot = { [weak self] snapshot in self?.snapshot = snapshot }
        link.onReachable = { [weak self] reachable in self?.reachable = reachable }
        link.onFailure = { [weak self] message in self?.note = message }
        link.start()
    }

    func send(_ command: String, text: String? = nil) {
        note = nil
        link.send(command, text: text, requestID: snapshot.askID)
    }
}

/// WatchConnectivity on the watch. Its delegate calls arrive on a background queue: each copies plain values and hops to the main actor.
final class WatchSide: NSObject, WCSessionDelegate, @unchecked Sendable {
    @MainActor var onSnapshot: ((WatchSnapshot) -> Void)?
    @MainActor var onReachable: ((Bool) -> Void)?
    @MainActor var onFailure: ((String) -> Void)?

    func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(_ command: String, text: String?, requestID: String?) {
        var message: [String: Any] = ["cmd": command]
        if let text, !text.isEmpty { message["text"] = text }
        if let requestID { message["rid"] = requestID }
        let session = WCSession.default
        // Not reachable (the iPhone app is not running or the phone is away): sendMessage would fail at once. Queue it instead, so it is
        // delivered when the iPhone is back, and say so. A queued answer names its request, so it cannot answer the wrong question.
        guard session.isReachable else {
            queue(command, text, requestID)
            return
        }
        session.sendMessage(message, replyHandler: nil) { error in
            self.queue(command, text, requestID)   // the live send failed: it must not vanish
            let words = error.localizedDescription
            Task { @MainActor in self.onFailure?("The iPhone did not answer live (\(words)). Your tap is queued and goes when it is back.") }
        }
    }

    private func queue(_ command: String, _ text: String?, _ requestID: String?) {
        var message: [String: Any] = ["cmd": command]
        if let text, !text.isEmpty { message["text"] = text }
        if let requestID { message["rid"] = requestID }
        WCSession.default.transferUserInfo(message)
        Task { @MainActor in self.onFailure?("The iPhone is out of reach. Your tap is queued and goes when it is back.") }
    }

    private func took(_ values: [String: Any]) {
        let snapshot = WatchSnapshot(values)
        Task { @MainActor in self.onSnapshot?(snapshot) }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {
        took(session.receivedApplicationContext)
        let reachable = session.isReachable
        Task { @MainActor in self.onReachable?(reachable) }
        if reachable { session.sendMessage(["cmd": "state"], replyHandler: nil, errorHandler: nil) }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        took(applicationContext)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        took(message)
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in self.onReachable?(reachable) }
    }
}

struct WatchScreen: View {
    let model: WatchModel

    private static let orange = Color(red: 0.910, green: 0.392, blue: 0.118)

    private var label: String {
        switch model.snapshot.state {
        case "connecting": return "Connecting"
        case "listening": return "Listening"
        case "hearing": return "Hearing you"
        case "working": return "Working"
        case "speaking": return "Speaking"
        case "waitingApproval": return "Needs you"
        case "lost": return "Line lost"
        default: return model.snapshot.inCall ? "Press Talk" : "No call"
        }
    }

    private var dot: Color {
        switch model.snapshot.state {
        case "listening", "hearing": return .blue
        case "working": return Self.orange
        case "speaking": return .green
        case "waitingApproval": return .yellow
        case "lost": return .red
        default: return .gray
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(dot)
                        .frame(width: 10, height: 10)
                        .accessibilityHidden(true)
                    Text(label)
                        .font(.headline)
                }
                if let ask = model.snapshot.ask {
                    Text(ask)
                        .font(.footnote)
                        .lineLimit(5)
                } else if !model.snapshot.line.isEmpty {
                    Text(model.snapshot.line)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                }
                if model.snapshot.more > 0 {
                    Text("\(model.snapshot.more) more waiting")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if model.snapshot.ask != nil, !model.snapshot.options.isEmpty {
                    // a question: its answers as buttons, kept until a tap (the iPhone never answers for him)
                    if model.snapshot.longQuestion {
                        Text("Open on iPhone to answer.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(model.snapshot.options.enumerated()), id: \.offset) { index, name in
                            Button(name) { model.send("option", text: String(index)) }
                        }
                    }
                } else if model.snapshot.ask != nil, model.snapshot.canAnswer {
                    Button("Approve") { model.send("approve") }
                        .tint(Self.orange)
                    Button("Deny") { model.send("deny") }
                    TextFieldLink(prompt: Text("Say why")) {
                        Text("Deny with a message")
                    } onSubmit: { words in
                        model.send("deny", text: words)
                    }
                } else if model.snapshot.inCall, model.snapshot.tap {
                    Button(role: .destructive) {
                        model.send("end")
                    } label: {
                        Label("End", systemImage: "phone.down.fill")
                    }
                } else if model.snapshot.inCall {
                    Button {
                        model.send("talk")
                    } label: {
                        Label("Talk", systemImage: "mic.fill")
                    }
                    .tint(Self.orange)
                    Button {
                        model.send("replay")
                    } label: {
                        Label("Replay", systemImage: "arrow.counterclockwise")
                    }
                    Button(role: .destructive) {
                        model.send("end")
                    } label: {
                        Label("End", systemImage: "phone.down.fill")
                    }
                } else {
                    Text("Start the call on your iPhone.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let note = model.note {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(.red)
                } else if !model.reachable {
                    Text("iPhone not in reach.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
