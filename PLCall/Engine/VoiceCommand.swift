import Foundation

/// A few things he can say to the call itself. Only a turn that is exactly one of these phrases counts,
/// so a sentence that merely contains "stop" still goes to the session.
enum VoiceCommand: Equatable {
    case stop, again, slower, faster, end

    private static let phrases: [String: VoiceCommand] = [
        "stop": .stop, "hold on": .stop, "wait": .stop, "quiet": .stop, "be quiet": .stop, "stop talking": .stop, "pause": .stop,
        "say that again": .again, "say it again": .again, "repeat that": .again, "repeat": .again, "replay": .again, "come again": .again,
        "slower": .slower, "slow down": .slower, "talk slower": .slower, "speak slower": .slower,
        "faster": .faster, "speed up": .faster, "talk faster": .faster, "speak faster": .faster,
        "end the call": .end, "end call": .end, "hang up": .end
    ]

    static func parse(_ heard: String) -> VoiceCommand? {
        let words = heard.lowercased().split { !$0.isLetter }.joined(separator: " ")
        return phrases[words]
    }
}

/// Wake word mode: the mic stays open, and only words after his name for the session are sent.
enum WakeWord {
    /// "Claude" and the ways the transcriber writes it.
    static let names: Set<String> = ["claude", "claud", "claudes", "clawed", "cloud", "clod", "clyde"]

    /// The words after the name, "" when the name was all he said, nil when the name is not there.
    static func after(_ heard: String) -> String? {
        let words = heard.split(separator: " ")
        guard let index = words.firstIndex(where: { names.contains($0.lowercased().filter(\.isLetter)) }) else { return nil }
        return words[(index + 1)...].joined(separator: " ")
    }
}
