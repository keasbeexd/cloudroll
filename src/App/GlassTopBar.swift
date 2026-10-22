import SwiftUI

/// Native Liquid Glass bar in place of Memories' mobile header: the view's title on the
/// left, Search and Upload on the right. Memories reserves 45pt for its header, which
/// this bar fills.
struct GlassTopBar: View {
    let title: String
    let onSearch: () -> Void
    let onUpload: () -> Void

    var body: some View {
        HStack {
            Text(title)
                .font(.headline)
                .padding(.horizontal, 16)
                .frame(height: 40)
                .modifier(GlassBackground(shape: Capsule()))
            Spacer()
            HStack(spacing: 0) {
                button("Search", symbol: "magnifyingglass", action: onSearch)
                button("Upload", symbol: "icloud.and.arrow.up", action: onUpload)
            }
            .padding(.horizontal, 4)
            .frame(height: 40)
            .modifier(GlassBackground(shape: Capsule()))
        }
        .padding(.horizontal, 16)
        .padding(.top, 2)
    }

    private func button(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 40)
                .contentShape(Rectangle())
        }
        .foregroundStyle(.primary)
        .accessibilityLabel(title)
    }
}
