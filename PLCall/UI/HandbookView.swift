import SwiftUI

/// The handbook: what Call does and how to use it, in the app. A changed behaviour changes its entry here in the same commit.
struct HandbookView: View {
    private struct Entry: Identifiable {
        let id = UUID()
        let title: String
        let body: String
    }

    private struct Part: Identifiable {
        let id = UUID()
        let title: String
        let entries: [Entry]
    }

    private let parts: [Part] = [
        Part(title: "The call", entries: [
            Entry(title: "Call and End", body: "Press the round button to call your session on the PC. Talk, stop, and Claude answers out loud. Press it again to end. The call keeps going with the phone locked."),
            Entry(title: "AUTO and PUSH", body: "AUTO listens all the time. PUSH opens the mic only when you press Talk, in the app or on the Lock Screen."),
            Entry(title: "Cues", body: "A short tone means Claude is about to talk. \u{201C}Listening\u{201D} means it is your turn. \u{201C}Got it\u{201D} means your words were sent. \u{201C}Line dropped\u{201D} means the PC stopped answering."),
            Entry(title: "The pause", body: "Your words are sent after you go quiet. Settings sets how long it waits, from 1 to 4 seconds. Longer lets you stop and think mid-sentence."),
            Entry(title: "Voice commands", body: "Say only \u{201C}stop\u{201D} while Claude talks to cut it off. \u{201C}Say that again\u{201D}, \u{201C}slower\u{201D}, \u{201C}faster\u{201D} and \u{201C}end the call\u{201D} work any time. A sentence that merely contains these words goes to Claude as normal."),
            Entry(title: "Wake word", body: "Optional, in Settings. The mic stays open, but only what you say after \u{201C}Claude\u{201D} is sent, plus follow-ups within 20 seconds. Useful with other people or a TV in the room.")
        ]),
        Part(title: "Answering Claude", entries: [
            Entry(title: "Approvals", body: "When Claude needs permission it says what for and asks yes or no. Say yes or no, press Approve or Deny on the screen, the Lock Screen or the notification, or nod or shake with AirPods. Loose answers like \u{201C}yeah go ahead\u{201D} are read by the iPhone\u{2019}s own model when Apple Intelligence is on."),
            Entry(title: "Deny with a reason", body: "Use Reply on the notification and say why, or the Explain and Other way buttons on the Lock Screen. Claude gets your words."),
            Entry(title: "Questions", body: "When Claude asks you to pick, say the option\u{2019}s name or its number.")
        ]),
        Part(title: "When you are not on a call", entries: [
            Entry(title: "Claude rings you", body: "With Stay reachable on, the phone rings like a call when Claude needs an approval or a question answered. Pick up and the question is read out. With AirPods, Siri announces it; nod twice to answer, shake twice to decline."),
            Entry(title: "Declining", body: "On a locked iPhone the system shows only slide to answer. Leave it: after 30 seconds the ring stops and a Missed call from Claude notice appears with the buttons. With the phone unlocked, the ring has a Decline button."),
            Entry(title: "Answering from the notice or the watch", body: "A question\u{2019}s notice carries its options as buttons, and an approval\u{2019}s carries Approve and Deny. They reach the watch when the phone is locked. The watch\u{2019}s Double Tap presses the first button: Approve, or the first option."),
            Entry(title: "A real call comes in", body: "During a call with Claude, choose Hold & Accept. Claude goes quiet. When you hang up, it picks up again and reads a waiting question once more. Claude never rings while you are on another call."),
            Entry(title: "When Claude is waiting", body: "After Claude finishes and you have not answered, the phone rings once after the time you pick in Settings. It does not ring while the session keeps moving."),
            Entry(title: "Its limits", body: "Staying reachable uses some battery. If iOS closes the app (low memory, Low Power Mode), nothing can ring until you open Call again.")
        ]),
        Part(title: "The rest", entries: [
            Entry(title: "Lock Screen and Dynamic Island", body: "The call\u{2019}s state and the conversation, with Talk in PUSH mode, Approve and Deny when asked, and End."),
            Entry(title: "Music mode", body: "In Settings. No phone-style call, so your music keeps playing. It uses the iPhone\u{2019}s own microphone. Starts with the next call."),
            Entry(title: "The voice", body: "Pick it in the voice list. The iPhone voice uses the best one installed: download Ava or Zoe (Premium) in Settings > Accessibility > Spoken Content > Voices. Pace and Pitch are in Call\u{2019}s Settings."),
            Entry(title: "AirPods", body: "Press the stem to talk, press twice to replay, three times to go back to listening."),
            Entry(title: "Updates", body: "New versions arrive in SideStore. Turn on LocalDevVPN to update or refresh, then switch back to Tailscale. Refresh at least once every 7 days."),
            Entry(title: "Capability probe", body: "Settings > Capability probe tests each feature on this iPhone and says pass or fail with the reason.")
        ])
    ]

    var body: some View {
        List {
            ForEach(parts) { part in
                Section {
                    ForEach(part.entries) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.title)
                                .plFont(.headline)
                            Text(entry.body)
                                .plFont(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                        .accessibilityElement(children: .combine)
                    }
                } header: {
                    Text(part.title)
                        .plFont(.footnote)
                }
            }
        }
    }
}
