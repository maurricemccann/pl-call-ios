import SwiftUI

/// His pattern behind the content, calmed by a dark scrim so the words stay readable. Content layer: not glass.
struct Backdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ZStack {
            Color.black
            if !reduceTransparency {
                RadialGradient(colors: [T.orange.opacity(0.20), .clear], center: .top, startRadius: 0, endRadius: 440)
                // the tile is black ink on clear: on a dark screen it is drawn as pale ink, faint, as on the R1
                Image("Backdrop")
                    .renderingMode(.template)
                    .resizable(resizingMode: .tile)
                    .foregroundStyle(Color.white.opacity(contrast == .increased ? 0.06 : 0.15))
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// The session state dot. Its words always sit beside it (see `CallState.plLabel`).
struct StateDot: View {
    let state: CallState

    var body: some View {
        Image(systemName: "circle.fill")
            .font(.system(size: 10))
            .foregroundStyle(state.plDotColor)
            .symbolEffect(.pulse, isActive: state == .hearing)
            .accessibilityHidden(true)
    }
}

/// Claude's avatar: a coral burst on a dark disc, inside a presence ring.
struct ClaudeAvatar: View {
    let ring: Color
    var speaking = false
    var size: CGFloat = 46

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !speaking)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            // two slow waves together read as speech, not a metronome
            let swell = speaking ? 1 + 0.045 * (sin(t * 7.1) * 0.6 + sin(t * 11.3) * 0.4) : 1
            face.scaleEffect(swell)
        }
    }

    private var face: some View {
        ZStack {
            Circle().fill(Color(uiColor: .secondarySystemBackground))
            ForEach(0..<6, id: \.self) { ray in
                Capsule()
                    .fill(T.coral)
                    .frame(width: size * 0.08, height: size * 0.5)
                    .rotationEffect(.degrees(Double(ray) * 30))
            }
        }
        .padding(size * 0.1)
        .overlay {
            Circle().strokeBorder(ring, lineWidth: max(2, size * 0.05))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The small hand-drawn heading used on the card and the sheets.
struct HandHeading: View {
    let text: String

    var body: some View {
        Text(text)
            .plHand(15, relativeTo: .subheadline)
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }
}

/// An icon with a line of words: the icon carries the colour, the words carry the meaning.
struct NoteLine: View {
    let symbol: String
    let tint: Color
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(text)
                .plFont(.footnote)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
        }
    }
}

/// Siri's Edge Light: a soft glow turning round the screen edge while the mic is open; it swells with his voice.
struct EdgeLight: View {
    let level: Double

    private static let colors: [Color] = [
        Color(uiColor: .systemBlue), Color(uiColor: .systemPurple), Color(uiColor: .systemPink),
        Color(uiColor: .systemOrange), Color(uiColor: .systemBlue),
    ]

    var body: some View {
        let loud = min(1, max(0, level))
        TimelineView(.animation) { context in
            let seconds = context.date.timeIntervalSinceReferenceDate
            let turn = seconds.truncatingRemainder(dividingBy: 12) * 30
            RoundedRectangle(cornerRadius: 52, style: .continuous)
                .strokeBorder(
                    AngularGradient(colors: Self.colors, center: .center, angle: .degrees(turn)),
                    lineWidth: 5 + 9 * loud
                )
                .blur(radius: 9)
        }
        .opacity(0.45 + 0.55 * loud)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
