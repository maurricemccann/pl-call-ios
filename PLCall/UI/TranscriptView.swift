import SwiftUI

/// The conversation in Messages' shape: his turns blue and trailing, Claude's leading, system lines small and centred.
/// Plain surfaces only: the content layer never wears Liquid Glass.
struct TranscriptView: View {
    let model: CallModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorSchemeContrast) private var contrast

    // explicit: a view with private state must not depend on the synthesized initializer staying internal
    init(model: CallModel) { self.model = model }

    private static let bottomID = "transcript-bottom"
    private static let runGap: TimeInterval = 300   // a time stamp between runs more than five minutes apart

    private struct Row: Identifiable {
        let turn: Turn
        let stamp: Bool
        let startsRun: Bool
        let endsRun: Bool
        var id: UUID { turn.id }
    }

    private var rows: [Row] {
        let turns = model.turns
        var out: [Row] = []
        var lastSpoken: Date?
        for index in turns.indices {
            let turn = turns[index]
            var stamp = false
            if turn.who != .system {
                if let last = lastSpoken {
                    stamp = turn.date.timeIntervalSince(last) > Self.runGap
                } else {
                    stamp = true
                }
                lastSpoken = turn.date
            }
            var startsRun = true
            if index > 0, !stamp {
                startsRun = turns[index - 1].who != turn.who
            }
            var endsRun = true
            if index + 1 < turns.count {
                let next = turns[index + 1]
                let sameSpeaker = next.who == turn.who
                let close = next.date.timeIntervalSince(turn.date) <= Self.runGap
                endsRun = !(sameSpeaker && close)
            }
            out.append(Row(turn: turn, stamp: stamp, startsRun: startsRun, endsRun: endsRun))
        }
        return out
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if model.turns.isEmpty && !model.isClaudeTyping {
                        Text("Your words and Claude's replies show here")
                            .plFont(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 80)
                    }
                    ForEach(rows) { row in
                        rowView(row)
                            .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
                    }
                    if model.isClaudeTyping {
                        TypingBubble()
                            .padding(.top, T.gap)
                    }
                    Color.clear
                        .frame(height: 1)
                        .id(Self.bottomID)
                }
                .padding(.horizontal, T.margin)
                .padding(.vertical, T.gap)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.86), value: model.turns.count)
            .onChange(of: model.turns.count) { _, _ in scrollToNewest(proxy) }
            .onChange(of: model.turns.last?.text) { _, _ in scrollToNewest(proxy) }
            .onChange(of: model.isClaudeTyping) { _, _ in scrollToNewest(proxy) }
        }
    }

    private func scrollToNewest(_ proxy: ScrollViewProxy) {
        withAnimation(PLMotion.standard(reduce: reduceMotion)) {
            proxy.scrollTo(Self.bottomID, anchor: .bottom)
        }
    }

    /// Room left beside a bubble, so it stops near 70% of the width; almost none at accessibility sizes.
    private var gutter: CGFloat { typeSize.isAccessibilitySize ? 24 : 96 }

    private var sentFill: AnyShapeStyle {
        if contrast == .increased { return AnyShapeStyle(T.sentContrast) }
        return AnyShapeStyle(LinearGradient(colors: [T.sentTop, T.sentBottom], startPoint: .top, endPoint: .bottom))
    }

    @ViewBuilder
    private func rowView(_ row: Row) -> some View {
        VStack(spacing: 0) {
            if row.stamp {
                Text(row.turn.date, style: .time)
                    .plFont(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
                    .padding(.bottom, 2)
            }
            switch row.turn.who {
            case .system:
                Text(row.turn.text)
                    .plFont(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            case .me:
                bubble(row, mine: true)
            case .claude:
                bubble(row, mine: false)
            }
        }
    }

    private func bubble(_ row: Row, mine: Bool) -> some View {
        // shortcut: no drawn tail; the last bubble of a run gets a tight corner on the speaker's side. Draw Messages' tail if he asks.
        let corner: CGFloat = row.endsRun ? T.bubbleTail : T.bubbleRadius
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: T.bubbleRadius,
            bottomLeadingRadius: mine ? T.bubbleRadius : corner,
            bottomTrailingRadius: mine ? corner : T.bubbleRadius,
            topTrailingRadius: T.bubbleRadius,
            style: .continuous
        )
        let fill: AnyShapeStyle = mine ? sentFill : AnyShapeStyle(T.received)
        let speaker = mine ? "You" : "Claude"
        return HStack(spacing: 0) {
            if mine { Spacer(minLength: gutter) }
            Text(row.turn.text)
                .plFont(.body)
                .foregroundStyle(mine ? Color.white : Color.primary)
                .textSelection(.enabled)
                .padding(.horizontal, T.bubblePadH)
                .padding(.vertical, T.bubblePadV)
                .background { shape.fill(fill) }
            if !mine { Spacer(minLength: gutter) }
        }
        .padding(.top, row.startsRun ? T.gap : 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(speaker): \(row.turn.text)")
    }
}

/// Three dots in Claude's bubble while Claude works. Still when Reduce Motion is on.
struct TypingBubble: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            TimelineView(.animation(minimumInterval: 0.05, paused: reduceMotion)) { context in
                let time = context.date.timeIntervalSinceReferenceDate
                HStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(Color.primary)
                            .frame(width: 8, height: 8)
                            .opacity(dotOpacity(index, at: time))
                    }
                }
            }
            .padding(.horizontal, T.bubblePadH)
            .padding(.vertical, T.bubblePadV + 4)
            .background { Capsule().fill(T.received) }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Claude is working")
    }

    private func dotOpacity(_ index: Int, at time: TimeInterval) -> Double {
        if reduceMotion { return 0.6 }
        let phase = time / 1.2 - Double(index) * 0.18
        let lit = max(0, sin(phase * 2 * Double.pi))
        return 0.35 + 0.55 * lit
    }
}
