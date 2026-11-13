import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

// The Live Activity: Lock Screen, StandBy, Dynamic Island and the watch Smart Stack.
// It draws only what the app put in the content state. It never uses the network.

/// The two ready-made answers. Both deny, and tell the session what to do next.
enum PresetReply {
    static let explain = "Not yet. Explain what this does first."
    static let otherWay = "No. Find a different way."
}

struct CallLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CallActivityAttributes.self) { context in
            CallActivityView(content: context.state)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    IslandSymbol(content: context.state)
                        .font(.title2)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    EndButton(compact: true, tinted: context.state.askID == nil)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(WidgetStyle.label(WidgetStyle.state(context.state.state)))
                        .font(WidgetStyle.text(18, .headline, strong: true))
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        DetailLine(content: context.state, lines: 2)
                        if context.state.askID != nil {
                            AnswerRow()
                        } else if context.state.push == true {
                            TalkButton()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                IslandSymbol(content: context.state)
            } compactTrailing: {
                StateDot(state: WidgetStyle.state(context.state.state), size: 12)
                    .accessibilityLabel(WidgetStyle.label(WidgetStyle.state(context.state.state)))
            } minimal: {
                IslandSymbol(content: context.state)
            }
            .keylineTint(WidgetStyle.accent)
        }
        .supplementalActivityFamilies([.small, .medium])
    }
}

/// Lock Screen and StandBy (medium) and the watch Smart Stack (small).
struct CallActivityView: View {
    let content: CallActivityAttributes.ContentState
    @Environment(\.activityFamily) private var family

    private var state: CallState { WidgetStyle.state(content.state) }
    private var hasAsk: Bool { content.askID != nil }

    var body: some View {
        if family == .small {
            small
        } else {
            medium
        }
    }

    /// Kept under the 160 pt the Lock Screen allows: header, two lines, one row of answers.
    private var medium: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                StateDot(state: state, size: 12)
                Text(WidgetStyle.label(state))
                    .font(WidgetStyle.text(18, .headline, strong: true))
                    .lineLimit(1)
                Spacer(minLength: 8)
                EndButton(compact: false, tinted: !hasAsk)
            }
            DetailLine(content: content, lines: 2)
            if hasAsk {
                AnswerRow()
            } else if content.push == true {
                TalkButton()
            }
        }
        .padding(14)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    /// The watch has room for the state, one line, and the two answers.
    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                StateDot(state: state, size: 10)
                Text(WidgetStyle.label(state))
                    .font(WidgetStyle.text(16, .headline, strong: true))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            if hasAsk {
                HStack(spacing: 6) {
                    Button(intent: ApproveIntent()) {
                        Text("Approve")
                    }
                    .tint(WidgetStyle.accent)
                    Button(intent: DenyIntent()) {
                        Text("Deny")
                    }
                }
                .font(WidgetStyle.text(14, .footnote, strong: true))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            } else {
                DetailLine(content: content, lines: 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// What is being asked while an answer is needed, otherwise the last line said.
struct DetailLine: View {
    let content: CallActivityAttributes.ContentState
    let lines: Int

    /// A question carries text but no askID (no buttons can answer it here), so the text alone marks an ask.
    private var isAsking: Bool { content.askID != nil || content.askText != nil }

    private var words: String {
        if isAsking {
            return content.askText ?? "Waiting for your answer."
        }
        return content.line
    }

    var body: some View {
        Text(words)
            .font(WidgetStyle.text(14, .footnote))
            .foregroundStyle(isAsking ? HierarchicalShapeStyle.primary : HierarchicalShapeStyle.secondary)
            .lineLimit(lines)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Approve, Deny and the two ready-made answers. Only Approve is tinted: it is the one primary action.
struct AnswerRow: View {
    var body: some View {
        HStack(spacing: 6) {
            Button(intent: ApproveIntent()) {
                Text("Approve").frame(maxWidth: .infinity, minHeight: 28)
            }
            .buttonStyle(.borderedProminent)
            .tint(WidgetStyle.accent)
            Button(intent: DenyIntent()) {
                Text("Deny").frame(maxWidth: .infinity, minHeight: 28)
            }
            .buttonStyle(.bordered)
            Button(intent: PresetReplyIntent(text: PresetReply.explain)) {
                Text("Explain").frame(maxWidth: .infinity, minHeight: 28)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Deny and ask for an explanation")
            Button(intent: PresetReplyIntent(text: PresetReply.otherWay)) {
                Text("Other way").frame(maxWidth: .infinity, minHeight: 28)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Deny and ask for a different way")
        }
        .font(WidgetStyle.text(14, .footnote, strong: true))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

/// PUSH mode: opens the mic for one turn from the Lock Screen, with no unlock.
struct TalkButton: View {
    var body: some View {
        Button(intent: TalkIntent()) {
            Label("Talk", systemImage: "mic.fill")
                .font(WidgetStyle.text(16, .headline, strong: true))
                .frame(maxWidth: .infinity, minHeight: 32)
        }
        .buttonStyle(.borderedProminent)
        .tint(WidgetStyle.accent)
        .accessibilityLabel("Talk: open the microphone for one turn")
    }
}

/// Ends the call. Red only when nothing else on the surface is tinted.
struct EndButton: View {
    let compact: Bool
    let tinted: Bool

    var body: some View {
        Button(intent: EndCallIntent()) {
            if compact {
                Image(systemName: "phone.down.fill")
            } else {
                Label("End", systemImage: "phone.down.fill")
                    .font(WidgetStyle.text(14, .footnote, strong: true))
            }
        }
        .buttonStyle(.bordered)
        .tint(tinted ? Color.red : nil)
        .accessibilityLabel("End the call")
    }
}

/// The state as one symbol, for the small Dynamic Island shapes.
struct IslandSymbol: View {
    let content: CallActivityAttributes.ContentState

    var body: some View {
        Image(systemName: WidgetStyle.symbol(WidgetStyle.state(content.state)))
            .foregroundStyle(WidgetStyle.color(WidgetStyle.state(content.state)))
            .accessibilityLabel(WidgetStyle.label(WidgetStyle.state(content.state)))
    }
}
