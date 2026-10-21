import SwiftUI

/// Native Liquid Glass toolbar shown while photos are selected, in place of Memories' bar.
struct SelectionToolbar: View {
    let label: String
    let onAction: (SelectionController.Action) -> Void
    let onMore: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 34, height: 34)
                }
                .accessibilityLabel("Cancel selection")
                Text(label)
                    .font(.subheadline.weight(.semibold))
                    .padding(.trailing, 10)
            }
            .padding(4)
            .modifier(GlassBackground(shape: Capsule()))

            HStack(spacing: 0) {
                ForEach(SelectionController.Action.allCases, id: \.self) { action in
                    toolbarButton(action.title, symbol: action.symbol, role: action == .delete ? .destructive : nil) {
                        onAction(action)
                    }
                }
                toolbarButton("More", symbol: "ellipsis", role: nil, action: onMore)
            }
            .padding(.horizontal, 6)
            .frame(height: 62)
            .modifier(GlassBackground(shape: Capsule()))
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func toolbarButton(_ title: String, symbol: String, role: ButtonRole?, action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .semibold))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .foregroundStyle(role == .destructive ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
        .accessibilityLabel(title)
    }
}

/// Liquid Glass on iOS 26, a material on earlier versions.
struct GlassBackground<S: Shape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: shape)
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        }
    }
}
