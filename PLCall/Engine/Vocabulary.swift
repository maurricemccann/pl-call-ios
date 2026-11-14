import Foundation

/// His own words for the ears (Psyclaupse, GlyphGuy, colourway, pl-os ...), so the recogniser stops guessing "the ball" for "the call".
/// Shipped in the app as vocab.txt, built from his notes by the PC's vocab script, and refreshed from the PC (GET /vocab) when the line connects.
enum Vocabulary {
    private static let cacheKey = "plcall.vocabulary"

    static func bundled() -> [String] {
        guard let url = Bundle.main.url(forResource: "vocab", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    static func cached() -> [String] {
        UserDefaults.standard.stringArray(forKey: cacheKey) ?? []
    }

    static func remember(_ words: [String]) {
        UserDefaults.standard.set(Array(words.prefix(500)), forKey: cacheKey)
    }

    /// Lists joined in order, each word once (case ignored). The first list wins ties, so his config's words come first.
    static func merged(_ lists: [String]...) -> [String] {
        var seen = Set<String>()
        return lists.flatMap { $0 }.filter { seen.insert($0.lowercased()).inserted }
    }
}
