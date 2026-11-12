import SwiftUI

/// A permission request: what it is for, the command or file, a short note, then Approve or Deny.
/// It sits above the bottom bar until it is answered here, by voice, from the lock screen or on the PC.
struct ApproveCard: View {
    let forWhat: String
    let what: String
    let onAnswer: (Bool, String?) -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var note = ""
    @FocusState private var noteFocused: Bool

    // explicit: a view with private state must not depend on the synthesized initializer staying internal
    init(forWhat: String, what: String, onAnswer: @escaping (Bool, String?) -> Void) {
        self.forWhat = forWhat
        self.what = what
        self.onAnswer = onAnswer
    }

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }   // at the largest text sizes the card scrolls instead of cutting its words
        }
        .frame(maxHeight: 420)   // the bottom inset barely limits height: this cap is what makes the scrolling form win at AX5
        .padding(T.margin)
        // content, not a control: a plain plate (HIG), the glass stays on its buttons
        .background(T.plate, in: RoundedRectangle(cornerRadius: T.cardRadius, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Claude asks for permission")
    }

    private var trimmedNote: String? {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            HandHeading(text: "CLAUDE ASKS")
            Text(forWhat)
                .plFont(.title3)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            if !what.isEmpty {
                ViewThatFits(in: .vertical) {
                    detail
                    ScrollView { detail }
                }
                .frame(maxHeight: 120)
                .background(T.well, in: RoundedRectangle(cornerRadius: T.wellRadius, style: .continuous))
                .accessibilityLabel("Command or file")
                .accessibilityValue(what)
            }
            TextField("Add a note…", text: $note)
                .plFont(.callout)
                .focused($noteFocused)
                .submitLabel(.done)
                .padding(.horizontal, 12)
                .frame(minHeight: T.touch)
                .background(T.well, in: Capsule())
                .accessibilityLabel("Note to send with your answer")
            if typeSize.isAccessibilitySize {
                VStack(spacing: T.gap) {
                    approveButton
                    denyButton
                }
            } else {
                HStack(spacing: T.gap) {
                    approveButton
                    denyButton
                }
            }
        }
    }

    /// The command or the file, in the system's monospaced design so columns and paths keep their shape.
    private var detail: some View {
        Text(what)
            .font(.system(.footnote, design: .monospaced))
            .foregroundStyle(.primary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
    }

    /// Approve comes first, as it does in the notification, so the same order holds everywhere.
    private var approveButton: some View {
        Button {
            noteFocused = false
            onAnswer(true, trimmedNote)
        } label: {
            Label("Approve", systemImage: "checkmark")
                .plFont(.headline)
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity, minHeight: 50)
                .contentShape(Capsule())
        }
        .glassControl(tint: T.orange)
    }

    private var denyButton: some View {
        Button {
            noteFocused = false
            onAnswer(false, trimmedNote)
        } label: {
            Label("Deny", systemImage: "xmark")
                .plFont(.headline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, minHeight: 50)
                .contentShape(Capsule())
        }
        .glassControl()
    }
}
