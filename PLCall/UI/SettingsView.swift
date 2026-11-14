import SwiftUI

/// Settings: the voice, the listening mode, the capability probe, forget the config, about.
struct SettingsView: View {
    let model: CallModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmForget = false
    @AppStorage("plcall.edgeLight") private var edgeLight = false
    @AppStorage("plcall.micMeter") private var micMeter = true
    @AppStorage("plcall.confirmUnsure") private var confirmUnsure = true
    @AppStorage("plcall.confirmBelow") private var confirmBelow = Heard.defaultThreshold
    @AppStorage("plcall.idleRingMinutes") private var idleMinutes = 10
    @AppStorage("plcall.ringSeconds") private var ringSeconds = 15
    @AppStorage("plcall.duckLevel") private var duckLevel = 2
    @AppStorage("plcall.customRing") private var customRing = true
    @AppStorage("plcall.useSpokenContent") private var useSpokenContent = false
    @State private var contactNote: String?
    @AppStorage(VoiceTuning.pauseKey) private var pause = VoiceTuning.defaultPause
    @AppStorage(VoiceTuning.rateKey) private var voiceRate = VoiceTuning.defaultRate
    @AppStorage(VoiceTuning.pitchKey) private var voicePitch = VoiceTuning.defaultPitch

    // explicit: a view with private state must not depend on the synthesized initializer staying internal
    init(model: CallModel) { self.model = model }

    private var voiceLabel: String {
        for voice in model.voices where voice.id == model.voiceID { return voice.label }
        return "Voice"
    }

    private var version: String {
        let value = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return (value ?? "1") + " (" + (build ?? "?") + ")"
    }

    private var handsFree: Binding<Bool> {
        Binding(get: { model.handsFree }, set: { model.setHandsFree($0) })
    }

    private var cues: Binding<Bool> {
        Binding(get: { model.spokenCues }, set: { model.setSpokenCues($0) })
    }

    private var reach: Binding<Bool> {
        Binding(get: { model.stayReachable }, set: { model.setStayReachable($0) })
    }

    private var ticks: Binding<Bool> {
        Binding(get: { model.workingSounds }, set: { model.setWorkingSounds($0) })
    }

    private var wake: Binding<Bool> {
        Binding(get: { model.wakeWord }, set: { model.setWakeWord($0) })
    }

    private var progress: Binding<Bool> {
        Binding(get: { model.speakProgress }, set: { model.setSpeakProgress($0) })
    }

    private var short: Binding<Bool> {
        Binding(get: { model.shortAnswers }, set: { model.setShortAnswers($0) })
    }

    private var music: Binding<Bool> {
        Binding(get: { model.musicMode }, set: { model.setMusicMode($0) })
    }

    private func sessionRow(_ id: String?, title: String) -> some View {
        Button {
            model.chooseSession(id)
        } label: {
            HStack {
                Text(title)
                    .plFont(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Spacer(minLength: T.gap)
                if model.chosenSession == id {
                    Image(systemName: "checkmark")
                        .foregroundStyle(T.orange)
                        .accessibilityLabel("Chosen")
                }
            }
        }
    }

    private func toggleRow(_ title: String, _ detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .plFont(.body)
                Text(detail)
                    .plFont(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        VoiceList(model: model)
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .principal) { title("Voice") }
                            }
                    } label: {
                        row("Voice", value: voiceLabel)
                    }
                    Toggle(isOn: handsFree) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Hands-free (AUTO)")
                                .plFont(.body)
                            Text("Off is PUSH: the mic opens only when you press Talk.")
                                .plFont(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    toggleRow("Cues", "A tone before Claude talks, \u{201C}Listening\u{201D} when it is your turn, \u{201C}Got it\u{201D} when your words are sent.", isOn: cues)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Pause before your words are sent: \(pause, specifier: "%.1f") s")
                            .plFont(.body)
                        Slider(value: $pause, in: VoiceTuning.pauseRange, step: 0.1) {
                            Text("Pause before your words are sent")
                        }
                        Text("Longer lets you stop and think mid-sentence. Starts with the next call.")
                            .plFont(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    toggleRow("Wake word", "Hands-free only. The mic stays open, but only what you say after \u{201C}Claude\u{201D} is sent, and follow-ups within 20 seconds.", isOn: wake)
                    toggleRow("Working sounds", "A soft tick while Claude works, so a long turn is not silence.", isOn: ticks)
                    toggleRow("Edge light", "A glow around the screen while the microphone hears you.", isOn: $edgeLight)
                    toggleRow("Mic meter", "A small level bar on the call screen, so in a loud place you can see the phone hears you above the room.", isOn: $micMeter)
                    toggleRow("Confirm when unsure", "When the phone is not sure of a word, it says \u{201C}I heard: \u{2026}, right?\u{201D} and waits for Yes or Again before sending.", isOn: $confirmUnsure)
                    if confirmUnsure {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Ask below \(Int((confirmBelow * 100).rounded())) percent sure")
                                .plFont(.body)
                            Slider(value: $confirmBelow, in: Heard.thresholdRange, step: 0.05) {
                                Text("Ask below this confidence")
                            }
                            Text("Higher asks more often. The confirm card shows how sure it was, so you can tune this in the place you use it.")
                                .plFont(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    toggleRow("Progress lines", "Claude\u{2019}s short notes while it works are spoken, not only the final answer.", isOn: progress)
                    toggleRow("Short spoken answers", "A long answer is said in a few sentences by the iPhone\u{2019}s own model. The full text stays on the screen.", isOn: short)
                    Picker(selection: $duckLevel) {
                        Text("Barely").tag(0)
                        Text("Some").tag(1)
                        Text("A lot").tag(2)
                    } label: {
                        Text("Lower other audio while on a call")
                            .plFont(.body)
                    }
                    toggleRow("Music mode", "No phone-style call, so your music keeps playing. Uses the iPhone\u{2019}s own microphone. Starts with the next call.", isOn: music)
                }

                Section {
                    sessionRow(nil, title: "The newest live session")
                    ForEach(model.sessions) { session in
                        sessionRow(session.id, title: session.title)
                    }
                } header: {
                    Text("Which session to call")
                        .plFont(.footnote)
                } footer: {
                    Text("Running more than one Claude Code session on the PC? Pick the one Call talks to. Pull down to refresh.")
                        .plFont(.footnote)
                }

                Section {
                    toggleRow("Stay reachable", "With no call up, Call keeps a quiet line open in the background, so Claude can ring you for an approval or a question. Uses some battery.", isOn: reach)
                    Button {
                        Task { contactNote = await ClaudeContact.add() ?? "Added. Calls now show Psyclaupse in Recents." }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Add Psyclaupse to Contacts")
                                .plFont(.body)
                            Text(contactNote ?? "So Recents and the ring show Psyclaupse with the heart mark, not an unknown caller.")
                                .plFont(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    toggleRow("Psyclaupse ringtone", "Its own soft ring. Off uses your iPhone\u{2019}s ringtone. Takes effect the next time the app opens.", isOn: $customRing)
                    Picker(selection: $ringSeconds) {
                        Text("10 seconds").tag(10)
                        Text("15 seconds").tag(15)
                        Text("20 seconds").tag(20)
                        Text("30 seconds").tag(30)
                        Text("45 seconds").tag(45)
                    } label: {
                        Text("Ring for")
                            .plFont(.body)
                    }
                    Picker(selection: $idleMinutes) {
                        Text("Never").tag(0)
                        Text("After 5 minutes").tag(5)
                        Text("After 10 minutes").tag(10)
                        Text("After 20 minutes").tag(20)
                        Text("After 30 minutes").tag(30)
                    } label: {
                        Text("Ring when Claude is waiting")
                            .plFont(.body)
                    }
                } header: {
                    Text("When you are not on a call")
                        .plFont(.footnote)
                } footer: {
                    Text("Claude rings at once for an approval or a question. A ring you leave stops after the time you pick and becomes a missed call. When Claude has finished and waits for you, it rings once after the wait you pick. To silence rings during a Focus, add Call in Settings > Focus > Focus Filters.")
                        .plFont(.footnote)
                }

                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Pace")
                            .plFont(.body)
                        Slider(value: $voiceRate, in: VoiceTuning.rateRange) {
                            Text("Pace")
                        } minimumValueLabel: {
                            Image(systemName: "tortoise.fill").accessibilityHidden(true)
                        } maximumValueLabel: {
                            Image(systemName: "hare.fill").accessibilityHidden(true)
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Pitch")
                            .plFont(.body)
                        Slider(value: $voicePitch, in: VoiceTuning.pitchRange) {
                            Text("Pitch")
                        }
                    }
                    toggleRow("Use my Spoken Content settings", "Your iPhone\u{2019}s Settings > Accessibility > Spoken Content rate, pitch and equalizer, in place of Pace and Pitch here.", isOn: $useSpokenContent)
                    Button {
                        model.previewVoice(Speaker.phone)
                    } label: {
                        Text("Hear it")
                            .plFont(.body)
                            .frame(minHeight: 28)
                    }
                } header: {
                    Text("iPhone voice")
                        .plFont(.footnote)
                }

                Section {
                    NavigationLink {
                        List {
                            ForEach(Array(RingLog.lines.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .plFont(.footnote)
                                    .textSelection(.enabled)
                            }
                            Button("Clear the log", role: .destructive) { RingLog.clear() }
                        }
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .principal) { title("Ring log") }
                        }
                    } label: {
                        Text("Ring log")
                            .plFont(.body)
                    }
                    NavigationLink {
                        HandbookView()
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .principal) { title("Handbook") }
                            }
                    } label: {
                        Text("Handbook")
                            .plFont(.body)
                    }
                    NavigationLink {
                        ProbeView(probe: model.probe)
                    } label: {
                        Text("Capability probe")
                            .plFont(.body)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        confirmForget = true
                    } label: {
                        Text("Forget config")
                            .plFont(.body)
                            .frame(minHeight: 28)
                    }
                }

                Section {
                    row("Version", value: version)
                    if let session = model.sessionTitle, !session.isEmpty {
                        row("Session", value: session)
                    }
                    Text("Text face: Jost, under the SIL Open Font License 1.1.")
                        .plFont(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("About")
                        .plFont(.footnote)
                }
            }
            .refreshable { await model.refreshSessions() }
            .task { await model.refreshSessions() }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { title("Settings") }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Done").plFont(.body, emphasized: true)
                    }
                }
            }
            .confirmationDialog("Forget this config?", isPresented: $confirmForget, titleVisibility: .visible) {
                Button("Forget config", role: .destructive) {
                    model.forgetConfig()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The line address and the call key are removed from this iPhone. Load the config file again to call.")
            }
        }
    }

    private func title(_ text: String) -> some View {
        Text(text)
            .plHand(20, relativeTo: .headline)
            .accessibilityAddTraits(.isHeader)
    }

    private func row(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: T.gap) {
            Text(label)
                .plFont(.body)
                .foregroundStyle(.primary)
            Spacer(minLength: T.gap)
            Text(value)
                .plFont(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}
