import SwiftUI

/// A question from the session: the question and its options as large rows. He can also answer out loud,
/// by the option's number or its words, so each row shows its number.
/// In Tap mode the rows are full-width buttons, several can be picked when the question allows it, and "Other..."
/// takes his own words (the keyboard's dictation works there). It never closes by itself.
struct QuestionSheet: View {
    let question: PermissionRequest.Question
    var tap = false
    var more = 0
    let onPick: (Int) -> Void
    var onSend: ([String]) -> Void = { _ in }
    var onHide: () -> Void = {}

    @State private var picked: Set<Int> = []
    @State private var writing = false
    @State private var typed = ""
    @FocusState private var typing: Bool

    // explicit: a view with private state must not depend on the synthesized initializer staying internal
    init(question: PermissionRequest.Question, tap: Bool = false, more: Int = 0, onPick: @escaping (Int) -> Void,
         onSend: @escaping ([String]) -> Void = { _ in }, onHide: @escaping () -> Void = {}) {
        self.question = question
        self.tap = tap
        self.more = more
        self.onPick = onPick
        self.onSend = onSend
        self.onHide = onHide
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    HandHeading(text: "CLAUDE ASKS")
                    Spacer(minLength: 0)
                    if tap {
                        // a way out for the sheet, not for the question: it stays waiting and the banner reopens it
                        Button("Hide", action: onHide)
                            .plFont(.footnote, emphasized: true)
                            .frame(minWidth: T.touch, minHeight: T.touch)
                            .accessibilityHint("The question keeps waiting")
                    }
                }
                .padding(.bottom, 6)
                if !question.header.isEmpty {
                    Text(question.header)
                        .plFont(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 2)
                }
                Text(question.question)
                    .plFont(.title3)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 12)
                    .accessibilityAddTraits(.isHeader)
                if tap {
                    tapRows
                } else {
                    ForEach(question.options.indices, id: \.self) { index in
                        if index > 0 { Divider() }
                        optionRow(index)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .padding(.bottom, 20)
        }
    }

    // MARK: Tap

    private var tapRows: some View {
        VStack(spacing: T.gap) {
            ForEach(question.options.indices, id: \.self) { index in
                tapButton(index)
            }
            if writing {
                TextField("Your own answer", text: $typed, axis: .vertical)
                    .plFont(.title3)
                    .focused($typing)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 56)
                    .background(T.well, in: RoundedRectangle(cornerRadius: T.wellRadius, style: .continuous))
                    .submitLabel(.send)
                    .onSubmit(sendTyped)
                    .accessibilityLabel("Your own answer")
                Button(action: sendTyped) {
                    Text("Send")
                        .plFont(.headline)
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .contentShape(Capsule())
                }
                .glassControl(tint: T.orange)
                .disabled(typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } else {
                Button {
                    writing = true
                    typing = true
                } label: {
                    Text("Other\u{2026}")
                        .plFont(.title3)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .contentShape(Capsule())
                }
                .glassControl()
            }
            if question.multiSelect, !picked.isEmpty {
                Button {
                    onSend(picked.sorted().map { question.options[$0] })
                } label: {
                    Text(picked.count == 1 ? "Send 1 answer" : "Send \(picked.count) answers")
                        .plFont(.headline)
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .contentShape(Capsule())
                }
                .glassControl(tint: T.orange)
            }
            if more > 0 {
                Text(more == 1 ? "1 more waiting" : "\(more) more waiting")
                    .plFont(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
    }

    private func tapButton(_ index: Int) -> some View {
        let option = question.options[index]
        let on = picked.contains(index)
        return Button {
            if question.multiSelect {
                if on { picked.remove(index) } else { picked.insert(index) }
            } else {
                onPick(index)
            }
        } label: {
            HStack(spacing: 12) {
                if question.multiSelect {
                    Image(systemName: on ? "checkmark.square.fill" : "square")
                        .foregroundStyle(on ? T.orange : Color.secondary)
                        .accessibilityHidden(true)
                }
                Text(option)
                    .plFont(.title3)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .contentShape(Capsule())
        }
        .glassControl()
        .accessibilityLabel("Option \(index + 1): \(option)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func sendTyped() {
        let words = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return }
        typing = false
        onSend([words])
    }

    // MARK: Classic

    private func optionRow(_ index: Int) -> some View {
        let option = question.options[index]
        return Button {
            onPick(index)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("\(index + 1)")
                    .plFont(.headline)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 24)
                Text(option)
                    .plFont(.title2)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 12)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Option \(index + 1): \(option)")
    }
}
