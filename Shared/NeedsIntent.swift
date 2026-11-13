import AppIntents

/// "Hey Siri, what does Psyclaupse need?": Siri reads what Claude is waiting on, from the state the app shares.
struct WhatDoesClaudeNeedIntent: AppIntent {
    static let title: LocalizedStringResource = "What Does Claude Need"
    static let description: IntentDescription? = "Says what Claude is waiting on, if anything."

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let now = SharedState.read()
        if let ask = now.ask, !ask.isEmpty {
            return .result(dialog: "Claude is waiting on you. \(ask) You can say approve in Psyclaupse, or deny in Psyclaupse.")
        }
        return .result(dialog: "Nothing is waiting. The last thing was: \(now.line)")
    }
}
