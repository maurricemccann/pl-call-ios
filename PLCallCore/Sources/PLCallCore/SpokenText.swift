import Foundation

/// Turns a written answer into what the voice says: sentences only. Code blocks, tables, links, file paths
/// and markup are left on the screen, and one line says so. Twin of the R1 Call's rules.
public enum SpokenText {
    public struct Result: Sendable, Equatable {
        public var sentences: [String]
        public var skippedSomething: Bool
    }

    public static let restOnScreen = "The rest is on the screen."

    public static func make(_ text: String, limit: Int = 1500) -> Result {
        var skipped = false
        var lines: [String] = []
        var inCode = false
        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") { inCode.toggle(); skipped = true; continue }
            if inCode { continue }
            if line.hasPrefix("|") || line.filter({ $0 == "|" }).count >= 2 { skipped = true; continue }   // a table row
            lines.append(line)
        }
        var t = lines.joined(separator: " ")
        t = replace(t, #"`([^`]*)`"#) { m in
            if looksLikePath(m) { skipped = true; return "" }
            return m
        }
        t = replace(t, #"\[([^\]]+)\]\([^)]+\)"#) { $0 }                                     // [label](link) -> label
        t = replaceAll(t, #"https?://\S+"#) { skipped = true; return "" }
        t = replaceAll(t, #"(?:[A-Za-z]:\\|~?/)[\w.\\/ -]*[\w]"#) { skipped = true; return "" }  // paths
        t = t.replacingOccurrences(of: #"[*_#>]+"#, with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: #"(^|\s)[-•]\s+"#, with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        if t.count > limit { t = String(t.prefix(limit)); skipped = true }

        var sentences = splitSentences(t)
        if sentences.isEmpty { sentences = [skipped ? restOnScreen : "Done."] }
        else if skipped { sentences.append(restOnScreen) }
        return Result(sentences: sentences, skippedSomething: skipped)
    }

    public static func splitSentences(_ t: String) -> [String] {
        var out: [String] = []
        var current = ""
        for ch in t {
            current.append(ch)
            if ch == "." || ch == "!" || ch == "?" {
                let s = current.trimmingCharacters(in: .whitespaces)
                if s.count > 1 { out.append(s) }
                current = ""
            }
        }
        let rest = current.trimmingCharacters(in: .whitespaces)
        if !rest.isEmpty { out.append(rest) }
        return out
    }

    static func looksLikePath(_ s: String) -> Bool {
        s.contains("/") || s.contains("\\") || s.range(of: #"\.[A-Za-z0-9]{1,5}$"#, options: .regularExpression) != nil
    }

    /// Replaces each match of a pattern with one capture group by the closure's result for that group.
    static func replace(_ s: String, _ pattern: String, _ f: (String) -> String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return s }
        let ns = s as NSString
        var out = ""
        var last = 0
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            out += f(m.numberOfRanges > 1 ? ns.substring(with: m.range(at: 1)) : ns.substring(with: m.range))
            last = m.range.location + m.range.length
        }
        return out + ns.substring(from: last)
    }

    static func replaceAll(_ s: String, _ pattern: String, _ f: () -> String) -> String {
        replace(s, pattern) { _ in f() }
    }
}
