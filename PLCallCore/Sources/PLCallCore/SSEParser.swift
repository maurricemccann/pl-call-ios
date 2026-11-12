import Foundation

/// Server-sent events, fed one line at a time (without the newline). A blank line ends an event.
/// Written by hand because line readers can drop the blank lines SSE uses as separators.
public struct SSEParser: Sendable {
    public struct Message: Sendable, Equatable {
        public var event: String?
        public var data: String
        public var id: String?
    }

    private var data: [String] = []
    private var event: String?
    private var id: String?

    public init() {}

    /// Returns a message when this line completes one.
    public mutating func feed(_ rawLine: String) -> Message? {
        let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : rawLine
        if line.isEmpty {
            defer { data = []; event = nil }
            guard !data.isEmpty else { return nil }
            return Message(event: event, data: data.joined(separator: "\n"), id: id)
        }
        if line.hasPrefix(":") { return nil }   // a comment / keep-alive
        let field: Substring, value: Substring
        if let colon = line.firstIndex(of: ":") {
            field = line[line.startIndex..<colon]
            var v = line[line.index(after: colon)...]
            if v.first == " " { v = v.dropFirst() }
            value = v
        } else {
            field = Substring(line); value = ""
        }
        switch field {
        case "data": data.append(String(value))
        case "event": event = String(value)
        case "id": id = String(value)
        default: break
        }
        return nil
    }

    /// Splits a chunk of bytes into lines, keeping a partial last line for the next call.
    public static func lines(appending chunk: String, to buffer: inout String) -> [String] {
        buffer += chunk
        var out: [String] = []
        while let nl = buffer.firstIndex(of: "\n") {
            out.append(String(buffer[buffer.startIndex..<nl]))
            buffer.removeSubrange(buffer.startIndex...nl)
        }
        return out
    }
}
