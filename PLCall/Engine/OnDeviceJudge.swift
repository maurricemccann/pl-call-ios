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

    /// A long written answer as two or three spoken sentences. nil when the model is not available, fails, or takes over six seconds.
    static func spoken(_ text: String) async -> String? {
        await withTaskGroup(of: String?.self) { group in
            group.addTask { await rewrite(text) }
            group.addTask {
                try? await Task.sleep(for: .seconds(6))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    private static func rewrite(_ text: String) async -> String? {
        #if canImport(FoundationModels)
        guard isAvailable else { return nil }
        let session = LanguageModelSession(instructions: """
            You turn a written message from an assistant into what a colleague would say out loud on a phone call.
            Use at most three short sentences and plain words. Keep every decision, number, question and anything the listener must do.
            No lists, no code, no file names. Add nothing that is not in the message. Reply with the spoken words only.
            """)
        guard let reply = try? await session.respond(to: String(text.prefix(4000))) else { return nil }
        let words = reply.content.trimmingCharacters(in: .whitespacesAndNewlines)
        return words.isEmpty ? nil : words
        #else
        return nil
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
