import SwiftUI
import WidgetKit

/// One reading of the shared call state.
struct StateEntry: TimelineEntry, Sendable {
    let date: Date
    let state: CallState
    let line: String
    let ask: String?
    let updated: Date?
    let shared: Bool   // false when this install has no shared store, so the state is not known here
}

/// Reads the state the app wrote. No network: the app redraws this widget whenever the state changes.
struct StateProvider: TimelineProvider {
    func placeholder(in context: Context) -> StateEntry {
        StateEntry(date: Date(), state: .listening, line: "", ask: nil, updated: nil, shared: true)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (StateEntry) -> Void) {
        completion(current())
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<StateEntry>) -> Void) {
        let next = Date().addingTimeInterval(15 * 60)   // a slow safety refresh; the app's own reload is the fast path
        completion(Timeline(entries: [current()], policy: .after(next)))
    }

    private func current() -> StateEntry {
        let now = SharedState.read()
        return StateEntry(
            date: Date(),
            state: now.state,
            line: now.line,
            ask: now.ask,
            updated: SharedState.updatedAt,
            shared: SharedState.isAvailable
        )
    }
}

struct StateWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: PLCallKinds.stateWidget, provider: StateProvider()) { entry in
            StateWidgetView(entry: entry)
        }
        .configurationDisplayName("Call")
        .description("Shows what the call is doing.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .systemSmall])
    }
}

struct StateWidgetView: View {
    let entry: StateEntry
    @Environment(\.widgetFamily) private var family

    private var title: String {
        entry.shared ? WidgetStyle.label(entry.state) : "Call"
    }

    private var symbol: String {
        entry.shared ? WidgetStyle.symbol(entry.state) : "phone.fill"
    }

    private var detail: String {
        if !entry.shared { return "Open to start" }
        if let ask = entry.ask, !ask.isEmpty { return ask }
        return entry.line
    }

    var body: some View {
        content
            .containerBackground(.fill.tertiary, for: .widget)
    }

    @ViewBuilder private var content: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: symbol)
                    .font(.title2)
                    .widgetAccentable()
            }
            .accessibilityLabel(title)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label(title, systemImage: symbol)
                    .font(WidgetStyle.text(16, .headline, strong: true))
                    .widgetAccentable()
                if !detail.isEmpty {
                    Text(detail)
                        .font(WidgetStyle.text(13, .caption))
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .accessoryInline:
            Label(title, systemImage: symbol)
        default:
            small
        }
    }

    /// The StandBy and Home Screen square.
    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                StateDot(state: entry.shared ? entry.state : .idle, size: 12)
                Text(title)
                    .font(WidgetStyle.text(18, .headline, strong: true))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Text(detail)
                .font(WidgetStyle.text(14, .footnote))
                .foregroundStyle(.secondary)
                .lineLimit(3)
            Spacer(minLength: 0)
            if let updated = entry.updated, entry.shared {
                Text(updated, style: .time)
                    .font(WidgetStyle.text(12, .caption2))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
