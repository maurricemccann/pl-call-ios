import SwiftUI

/// "I heard: ..., right?" with one tap each for Yes (send it) and Again (say it again). Shown while the ears are unsure of a word.
struct HeardCard: View {
    let check: HeardCheck
    let onAnswer: (Bool) -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    // explicit: a view with private state must not depend on the synthesized initializer staying internal
    init(check: HeardCheck, onAnswer: @escaping (Bool) -> Void) {
        self.check = check
        self.onAnswer = onAnswer
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HandHeading(text: "I HEARD")
            Text(check.text)
                .plFont(.title3)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Not sure of every word (\(Int((check.confidence * 100).rounded()))%). Yes sends it, Again says it over. You can also just say yes or again.")
                .plFont(.footnote)
                .foregroundStyle(.secondary)
            if typeSize.isAccessibilitySize {
                VStack(spacing: T.gap) {
                    yes
                    again
                }
            } else {
                HStack(spacing: T.gap) {
                    yes
                    again
                }
            }
        }
        .padding(T.margin)
        .background(T.plate, in: RoundedRectangle(cornerRadius: T.cardRadius, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("I heard: \(check.text). Right?")
    }

    private var yes: some View {
        Button {
            onAnswer(true)
        } label: {
            Label("Yes", systemImage: "checkmark")
                .plFont(.headline)
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity, minHeight: 50)
                .contentShape(Capsule())
        }
        .glassControl(tint: T.orange)
    }

    private var again: some View {
        Button {
            onAnswer(false)
        } label: {
            Label("Again", systemImage: "arrow.counterclockwise")
                .plFont(.headline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, minHeight: 50)
                .contentShape(Capsule())
        }
        .glassControl()
    }
}

/// The live mic level on the call screen: in a loud place it shows whether the phone hears you above the room.
/// It reads the level itself, so the dozen updates a second redraw only this bar.
struct MicMeter: View {
    let model: CallModel

    var body: some View {
        let level = model.isMuted ? 0 : min(1, max(0, model.meterLevel))
        HStack(spacing: 8) {
            Text(model.isMuted ? "MUTED" : "MIC")
                .plFont(.caption, emphasized: true)
                .foregroundStyle(.secondary)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.14))
                    Capsule()
                        .fill(level > 0.85 ? T.end : level > 0.35 ? T.call : Color(uiColor: .systemGray))   // green once it hears speech, red when it clips
                        .frame(width: max(4, proxy.size.width * level))
                }
            }
            .frame(width: 140, height: 6)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Microphone level")
        .accessibilityValue(model.isMuted ? "Muted" : "\(Int(level * 100)) percent")
    }
}
