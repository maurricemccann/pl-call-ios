import AppIntents

/// The shortcuts offered to Siri, Shortcuts and the Action button. App target only: an app has one provider.
struct CallShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartCallIntent(),
            phrases: [
                "Start a \(.applicationName)",
                "Start \(.applicationName)",
                "Open the line in \(.applicationName)"
            ],
            shortTitle: "Call",
            systemImageName: "phone.fill"
        )
        AppShortcut(
            intent: EndCallIntent(),
            phrases: [
                "End the \(.applicationName)",
                "Hang up \(.applicationName)"
            ],
            shortTitle: "End",
            systemImageName: "phone.down.fill"
        )
    }
}
