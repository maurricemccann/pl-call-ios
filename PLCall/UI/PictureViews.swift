import SwiftUI

/// A picture opened full screen.
struct ZoomItem: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// A picture Claude showed on the call: fetched through the line, tap to open it full screen.
struct TurnPicture: View {
    let model: CallModel
    let path: String
    let onOpen: (UIImage) -> Void
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Button {
                    onOpen(image)
                } label: {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 280, maxHeight: 360)
                        .clipShape(RoundedRectangle(cornerRadius: T.bubbleRadius, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Picture from Claude. Opens full screen")
            } else if failed {
                Label("The picture could not load", systemImage: "photo.badge.exclamationmark")
                    .plFont(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, T.bubblePadH)
                    .padding(.vertical, T.bubblePadV)
                    .background(T.received, in: RoundedRectangle(cornerRadius: T.bubbleRadius, style: .continuous))
            } else {
                ProgressView()
                    .frame(width: 120, height: 120)
            }
        }
        .task(id: path) {
            image = await model.loadImage(path)
            failed = image == nil
        }
    }
}

/// Full screen: pinch to zoom, drag when zoomed, double tap toggles, the X closes.
struct ZoomView: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var base: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var dragBase: CGSize = .zero

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .offset(offset)
                .gesture(
                    MagnifyGesture()
                        .onChanged { scale = min(8, max(1, base * $0.magnification)) }
                        .onEnded { _ in
                            base = scale
                            if scale <= 1 { reset() }
                        }
                )
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { drag in
                            guard scale > 1 else { return }
                            offset = CGSize(width: dragBase.width + drag.translation.width, height: dragBase.height + drag.translation.height)
                        }
                        .onEnded { _ in dragBase = offset }
                )
                .onTapGesture(count: 2) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        if scale > 1 { reset() } else { scale = 3; base = 3 }
                    }
                }
                .accessibilityLabel("Picture from Claude")
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: T.touch, height: T.touch)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassControl(in: Circle())
            .padding()
            .accessibilityLabel("Close")
        }
    }

    private func reset() {
        scale = 1; base = 1; offset = .zero; dragBase = .zero
    }
}
