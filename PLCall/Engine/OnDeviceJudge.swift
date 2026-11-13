import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Apple's on-device model, used for one thing: reading a loosely worded answer to "yes or no?".
/// It is only asked when the plain word match could not tell, and any doubt stays "unclear", so the app asks again.
enum OnDeviceJudge {
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if case .available = SystemLanguageModel.default.availability { return true }
        #endif
        return false
    }

    /// Why it cannot run, in the system's own words.
    static var unavailableReason: String {
        #if canImport(FoundationModels)
        return "The on-device model is not available: \(String(describing: SystemLanguageModel.default.availability)). Apple Intelligence must be on in Settings."
        #else
        return "This build has no on-device model."
        #endif
    }

    /// true = yes, false = no, nil = unclear or the model is not available.
    static func decision(_ heard: String) async -> Bool? {
        #if canImport(FoundationModels)
        guard isAvailable else { return nil }
        let words = String(heard.prefix(300))
        let session = LanguageModelSession(instructions: """
            A person was asked to allow or refuse an action, and answered out loud. Speech recognition may have misheard a word.
            Reply with exactly one word. YES if they clearly allow it. NO if they clearly refuse it.
            UNCLEAR if there is any doubt, if they ask a question, or if they talk about something else.
            """)
        guard let reply = try? await session.respond(to: "Their answer: \(words)") else { return nil }
        let word = reply.content.uppercased()
        if word.contains("UNCLEAR") { return nil }
        if word.contains("YES") { return true }
        if word.contains("NO") { return false }
        #endif
        return nil
    }
}
