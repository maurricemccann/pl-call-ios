import SwiftUI

/// Settings: the voice, the listening mode, the capability probe, forget the config, about.
struct SettingsView: View {
    let model: CallModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmForget = false

    // explicit: a view with private state must not depend on the synthesized initializer staying internal
    init(model: CallModel) { self.model = model }

    private var voiceLabel: String {
        for voice in model.voices where voice.id == model.voiceID { return voice.label }
        return "Voice"
    }

    private var version: String {
        let value = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return value ?? "1"
    }

    private var handsFree: Binding<Bool> {
        Binding(get: { model.handsFree }, set: { model.setHandsFree($0) })
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
