import AppIntents

/// A Focus filter: in Settings > Focus > (a Focus) > Focus Filters > Call, he chooses whether Claude may ring
/// while that Focus is on. When rings are off, the question or approval still arrives as a notification.
struct CallFocusFilter: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "Claude rings"
    static let description: IntentDescription? = "Choose whether Claude can ring you while this Focus is on. Questions and approvals still arrive as notifications."

    static let key = "plcall.focusAllowsRings"

    @Parameter(title: "Let Claude ring", default: false)
    var allowRings: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: allowRings ? "Claude can ring" : "Notifications only")
    }

    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(allowRings, forKey: Self.key)
        return .result()
    }

    /// True unless a Focus with this filter is on and says notifications only.
    static var ringsAllowed: Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? true
    }
}
