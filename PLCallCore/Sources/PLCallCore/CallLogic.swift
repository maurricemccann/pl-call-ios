import Foundation

/// The session state shown everywhere: the screen, the Live Activity, widgets, controls and the watch.
public enum CallState: String, Codable, Sendable, CaseIterable {
    case idle, connecting, listening, hearing, working, speaking, waitingApproval, lost
}

/// What the stream asks of the app.
public enum Ask: Sendable, Equatable {
    case permission(requestId: String, toolUseId: String?, forWhat: String, what: String)
    case question(requestId: String, toolUseId: String?, question: PermissionRequest.Question, input: JSONValue?)
}

public enum ReducerOutput: Sendable, Equatable {
    case speak(String)          // the answer to read, when Claude's turn ends
    case ask(Ask)               // a permission or a question
    case transcript(String)     // an assistant line for the screen
}

/// Port of the call page's onEvent(): keeps the latest words and speaks them when the turn ends.
public struct EventReducer: Sendable {
    public private(set) var lastSeq = 0
    public private(set) var lastSaid = ""
    public private(set) var waiting = false
    private var reply = ""

    public init(lastSeq: Int = 0) { self.lastSeq = lastSeq }

    /// Prime from the recent backlog: no speaking, only where to resume and what Replay reads.
    public mutating func prime(_ backlog: [SessionEvent]) {
        lastSeq = backlog.last?.sequenceNum ?? lastSeq
        if let e = backlog.last(where: { $0.role == "assistant" && !($0.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            lastSaid = e.text ?? ""
        }
    }

    /// After the app sends his words or an answer: wait for Claude's turn to end.
    public mutating func sent() { waiting = true; reply = "" }

    public mutating func ingest(_ e: SessionEvent) -> [ReducerOutput] {
        guard e.sequenceNum > lastSeq else { return [] }
        lastSeq = e.sequenceNum
        if e.isBlockingControl == true, let p = e.permissionRequest, let rid = e.requestId {
            waiting = false
            if let q = p.questions.first {
                return [.ask(.question(requestId: rid, toolUseId: e.toolUseId, question: q, input: p.input))]
            }
            return [.ask(.permission(requestId: rid, toolUseId: e.toolUseId, forWhat: p.forWhat, what: p.what))]
        }
        let text = (e.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if e.role == "assistant", !text.isEmpty { reply = e.text ?? "" }
        if waiting, e.type == "result" || e.isTurnEnd == true {
            waiting = false
            let t = reply.isEmpty ? "Done." : reply
            reply = ""
            lastSaid = t
            return [.transcript(t), .speak(t)]
        }
        if e.role == "assistant", !text.isEmpty { lastSaid = e.text ?? "" }
        return []
    }
}

/// Hearing "approve" or "deny", and picking a question's option, from what he said. Port of the call page.
public enum SpokenAnswer {
    public static func decision(_ heard: String) -> Bool? {
        let t = heard.lowercased()
        let no = t.range(of: #"\b(deny|denied|no|nope|don'?t|stop|cancel|reject)\b"#, options: .regularExpression) != nil
        let yes = t.range(of: #"\b(allow|allowed|approve|approved|yes|yeah|yep|ok|okay|go|sure|do it|accept|run it)\b"#, options: .regularExpression) != nil
        if yes == no { return nil }   // unclear: ask again
        return yes
    }

    public static func option(_ heard: String, of q: PermissionRequest.Question) -> Int? {
        let t = heard.lowercased()
        // an option's own name wins over a number word ("the blue one" is Blue, not option one)
        if let named = q.options.firstIndex(where: { t.contains($0.lowercased()) }) { return named }
        let words = ["one", "two", "three", "four"]
        for i in q.options.indices where i < words.count {
            if t.range(of: "\\b\(words[i])\\b", options: .regularExpression) != nil || t.range(of: "\\b\(i + 1)\\b", options: .regularExpression) != nil { return i }
        }
        return nil
    }
}

/// The request bodies for the bridge, exactly as the call page sends them.
public enum BridgeBody {
    public struct Send: Encodable { public let text: String }
    public struct Permission: Encodable {
        public let request_id: String
        public let decision: String
        public let tool_use_id: String?
        public let message: String?
    }
    public struct Dialog: Encodable {
        public struct Answer: Encodable { public let question: String; public let header: String; public let options: [String] }
        public let request_id: String
        public let status = "completed"
        public let subtype = "can_use_tool"
        public let answers: [Answer]
        public let input: JSONValue?
        public let tool_use_id: String?
    }

    public static func send(_ text: String) -> Send { Send(text: text) }

    public static func permission(requestId: String, toolUseId: String?, allow: Bool, message: String? = nil) -> Permission {
        let m = message?.trimmingCharacters(in: .whitespacesAndNewlines)
        return Permission(request_id: requestId, decision: allow ? "allow" : "deny", tool_use_id: toolUseId, message: (m?.isEmpty ?? true) ? nil : m)
    }

    public static func dialog(requestId: String, toolUseId: String?, question: PermissionRequest.Question, option: Int, input: JSONValue?) -> Dialog {
        Dialog(request_id: requestId,
               answers: [.init(question: question.question, header: question.header, options: [question.options[option]])],
               input: input, tool_use_id: toolUseId)
    }

    public static func json<T: Encodable>(_ body: T) -> Data {
        let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]
        return (try? e.encode(body)) ?? Data("{}".utf8)
    }
}

/// Quick replies: a plain one sends at once; an armed one (a slash command) sends only on a second tap within 3 s.
public struct QuickReplyArm: Sendable {
    public enum Outcome: Sendable, Equatable { case send(String), armed(String) }
    private var armedLabel: String?
    private var armedAt: Double = 0
    public static let window: Double = 3

    public init() {}

    public mutating func tap(_ r: PLCallConfig.QuickReply, now: Double) -> Outcome {
        if r.arm == true {
            if armedLabel == r.label, now - armedAt <= Self.window {
                armedLabel = nil
                return .send(r.send)
            }
            armedLabel = r.label; armedAt = now
            return .armed(r.label)
        }
        armedLabel = nil
        return .send(r.send)
    }
}
