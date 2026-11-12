import SwiftUI

/// The voice picker as a sheet: a hand-drawn title over the list.
struct VoicePickerView: View {
    let model: CallModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Voice")
                .plHand(28, relativeTo: .title)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 20)
                .padding(.top, 28)
            VoiceList(model: model)
        }
    }
}

/// The voices from the config, each with a preview button. Used by the sheet and by Settings.
struct VoiceList: View {
    let model: CallModel
    @State private var pickTick = 0

    // explicit: a view with private state must not depend on the synthesized initializer staying internal
    init(model: CallModel) { self.model = model }

    var body: some View {
        List {
            ForEach(model.voices, id: \.id) { voice in
                row(voice)
            }
        }
        .sensoryFeedback(PLHaptic.select, trigger: pickTick)
    }

    private func row(_ voice: PLCallConfig.Voice) -> some View {
        let selected = voice.id == model.voiceID
        return HStack(spacing: 12) {
            Button {
                pickTick += 1
                model.selectVoice(voice.id)
            } label: {
                HStack(spacing: T.gap) {
                    Text(voice.label)
                        .plFont(.body)
                        .foregroundStyle(.primary)
                    Spacer(minLength: T.gap)
                    if selected {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)
                    }
                }
                .frame(minHeight: T.touch)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(voice.label)
            .accessibilityAddTraits(selected ? .isSelected : [])

            Button {
                model.previewVoice(voice.id)
            } label: {
                Image(systemName: "play.circle")
                    .font(.system(size: 24))
                    .foregroundStyle(.primary)
                    .frame(width: T.touch, height: T.touch)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Preview \(voice.label)")
        }
    }
}
