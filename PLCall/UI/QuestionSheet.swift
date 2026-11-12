import SwiftUI

/// A question from the session: the question and its options as large rows. He can also answer out loud,
/// by the option's number or its words, so each row shows its number.
struct QuestionSheet: View {
    let question: PermissionRequest.Question
    let onPick: (Int) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HandHeading(text: "CLAUDE ASKS")
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
                ForEach(question.options.indices, id: \.self) { index in
                    if index > 0 { Divider() }
                    optionRow(index)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .padding(.bottom, 20)
        }
    }

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
