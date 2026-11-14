import Foundation

/// One stretch of what the ears heard: the words, how sure the recogniser was, and what else it thought it heard there.
public struct HeardSegment: Sendable, Equatable {
    public var text: String
    public var alternatives: [String]   // other readings of this same stretch, most likely first
    public var confidence: Double?      // 0...1 (the weakest real word in it), nil when the recogniser gave none

    public init(text: String, alternatives: [String] = [], confidence: Double? = nil) {
        self.text = text
        self.alternatives = alternatives
        self.confidence = confidence
    }
}

/// What a turn carries beyond its words: how unsure the ears were, and the other readings.
public enum Heard {
    /// Where "unsure" starts unless he moves it in Settings. A starting guess; the slider exists because only his phone can calibrate it.
    public static let defaultThreshold = 0.5
    public static let thresholdRange = 0.2...0.9

    /// The least sure part of the turn (a single garbled word is what matters, not the average), nil when nothing carried a confidence.
    public static func confidence(_ segments: [HeardSegment]) -> Double? {
        segments.compactMap(\.confidence).min()
    }

    public static func isUnsure(confidence: Double?, below threshold: Double) -> Bool {
        guard let confidence else { return false }
        return confidence < threshold
    }

    /// Whole-turn readings that differ from the words: the least sure stretch swapped for each of its alternatives, then the next least sure.
    public static func alternatives(_ segments: [HeardSegment], limit: Int = 3) -> [String] {
        let order = segments.indices.sorted { (segments[$0].confidence ?? 2) < (segments[$1].confidence ?? 2) }
        let best = join(segments.map(\.text))
        var seen: Set<String> = [bare(best)]
        var out: [String] = []
        for index in order {
            for alternative in segments[index].alternatives {
                let swapped = join(segments.indices.map { $0 == index ? alternative : segments[$0].text })
                guard out.count < limit, !swapped.isEmpty, seen.insert(bare(swapped)).inserted else { continue }
                out.append(swapped)
            }
        }
        return out
    }

    private static func join(_ parts: [String]) -> String {
        parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static func bare(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}

/// His answer to "I heard: ..., right?". Only a short whole reply counts, so a real sentence is never swallowed as a yes.
public enum ConfirmReply: Equatable, Sendable {
    case yes, again, other

    private static let yes: Set<String> = ["yes", "yeah", "yep", "yup", "right", "correct", "that's right", "thats right", "that is right", "sure", "ok", "okay", "send it", "go", "go ahead", "exactly"]
    private static let again: Set<String> = ["again", "no", "nope", "wrong", "not quite", "try again", "say again", "say that again", "once more", "no that's wrong", "that's wrong", "thats wrong"]

    public static func parse(_ heard: String) -> ConfirmReply {
        let words = heard.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
            .split { !($0.isLetter || $0 == "'") }.joined(separator: " ")
        if yes.contains(words) { return .yes }
        if again.contains(words) { return .again }
        return .other
    }
}
