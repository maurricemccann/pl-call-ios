import SwiftUI

/// The capability probe: each thing this install may or may not be able to do, run on his phone, with the reason when it fails.
/// Nothing is believed until it passes here.
struct ProbeView: View {
    let probe: ProbeModel

    var body: some View {
        List {
            ForEach(probe.items) { item in
                row(item)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Probe")
                    .plHand(20, relativeTo: .headline)
                    .accessibilityAddTraits(.isHeader)
            }
        }
    }

    private func isRunning(_ item: ProbeModel.Item) -> Bool {
        if case .running = item.result { return true }
        return false
    }

    private func row(_ item: ProbeModel.Item) -> some View {
        let id = item.id
        return VStack(alignment: .leading, spacing: 6) {
            Text(item.title)
                .plFont(.headline)
                .foregroundStyle(.primary)
            if !item.detail.isEmpty {
                Text(item.detail)
                    .plFont(.footnote)
                    .foregroundStyle(.secondary)
            }
            resultLine(item.result)
            Button {
                Task { await probe.run(id) }
            } label: {
                Text("Run")
                    .plFont(.callout, emphasized: true)
                    .padding(.horizontal, 18)
                    .frame(minHeight: T.touch)
                    .contentShape(Capsule())
            }
            .buttonStyle(.bordered)
            .disabled(isRunning(item))
            .accessibilityLabel("Run \(item.title)")
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func resultLine(_ result: ProbeModel.Item.Result) -> some View {
        switch result {
        case .untested:
            NoteLine(symbol: "circle", tint: Color(uiColor: .systemGray), text: "Not run yet")
        case .running:
            HStack(spacing: 6) {
                ProgressView()
                Text("Running")
                    .plFont(.footnote)
                    .foregroundStyle(.secondary)
            }
        case .pass:
            NoteLine(symbol: "checkmark.circle.fill", tint: T.call, text: "Passed")
        case .fail(let reason):
            NoteLine(symbol: "xmark.circle.fill", tint: T.end, text: "Failed: \(reason)")
        }
    }
}
