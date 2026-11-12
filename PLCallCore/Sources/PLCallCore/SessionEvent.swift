import Foundation

/// One event from the bridge's session stream. Every field is optional: the bridge sends many kinds.
public struct SessionEvent: Decodable, Sendable, Equatable {
    public var sequenceNum: Int
    public var role: String?
    public var text: String?
    public var type: String?
    public var isTurnEnd: Bool?
    public var isBlockingControl: Bool?
    public var requestId: String?
    public var toolUseId: String?
    public var permissionRequest: PermissionRequest?

    public init(sequenceNum: Int, role: String? = nil, text: String? = nil, type: String? = nil, isTurnEnd: Bool? = nil,
                isBlockingControl: Bool? = nil, requestId: String? = nil, toolUseId: String? = nil, permissionRequest: PermissionRequest? = nil) {
        self.sequenceNum = sequenceNum; self.role = role; self.text = text; self.type = type; self.isTurnEnd = isTurnEnd
        self.isBlockingControl = isBlockingControl; self.requestId = requestId; self.toolUseId = toolUseId; self.permissionRequest = permissionRequest
    }

    enum CodingKeys: String, CodingKey {
        case sequenceNum, role, text, type, isTurnEnd, isBlockingControl, requestId, toolUseId, permissionRequest
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sequenceNum = (try? c.decode(Int.self, forKey: .sequenceNum)) ?? Int((try? c.decode(Double.self, forKey: .sequenceNum)) ?? 0)
        role = try? c.decode(String.self, forKey: .role)
        text = try? c.decode(String.self, forKey: .text)
        type = try? c.decode(String.self, forKey: .type)
        isTurnEnd = try? c.decode(Bool.self, forKey: .isTurnEnd)
        isBlockingControl = try? c.decode(Bool.self, forKey: .isBlockingControl)
        requestId = try? c.decode(String.self, forKey: .requestId)
        toolUseId = try? c.decode(String.self, forKey: .toolUseId)
        permissionRequest = try? c.decode(PermissionRequest.self, forKey: .permissionRequest)
    }

    public static func decode(_ json: String) -> SessionEvent? {
        guard let d = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(SessionEvent.self, from: d)
    }
}

/// A blocking request: either a tool permission or a question with options (AskUserQuestion).
public struct PermissionRequest: Decodable, Sendable, Equatable {
    public struct Question: Sendable, Equatable {
        public var question: String
        public var header: String
        public var options: [String]
    }

    public var raw: JSONValue
    public var questions: [Question]
    public var input: JSONValue?

    public init(raw: JSONValue) {
        self.raw = raw
        input = raw["input"]
        questions = (raw["questions"]?.array ?? []).compactMap { q in
            guard let text = q["question"]?.string else { return nil }
            let opts = (q["options"]?.array ?? []).compactMap { $0["label"]?.string ?? $0.string }
            return Question(question: text, header: q["header"]?.string ?? "", options: opts)
        }
    }

    public init(from decoder: Decoder) throws {
        self.init(raw: try JSONValue(from: decoder))
    }

    public var isQuestion: Bool { !questions.isEmpty }

    /// One spoken line saying what the permission is for: its description first, else the tool's name.
    public var forWhat: String {
        for key in ["description", "message", "reason", "title", "prompt"] {
            if let s = raw[key]?.string, !s.trimmingCharacters(in: .whitespaces).isEmpty { return s }
        }
        if let d = input?["description"]?.string, !d.isEmpty { return d }
        let tool = raw["toolName"]?.string ?? raw["tool_name"]?.string ?? raw["tool"]?.string ?? "a tool"
        return "Claude wants to use \(tool)."
    }

    /// The detail shown on screen: the command or the file it touches.
    public var what: String {
        if let c = input?["command"]?.string { return c }
        if let f = input?["file_path"]?.string ?? input?["path"]?.string { return f }
        if let u = input?["url"]?.string { return u }
        return ""
    }
}
