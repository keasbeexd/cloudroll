import SwiftUI

/// Floating tab bar in place of Memories' own. Liquid Glass on iOS 26; a blurred
/// material capsule on earlier versions. `shell-navigation.js` reserves 78px plus the
/// safe area below Memories' scrollers: this 62pt bar, its 8pt margin and an 8pt gap.
struct GlassTabBar: View {
    let tabs: [NavState.Tab]
    let selected: NavState.Tab?
    let onSelect: (NavState.Tab) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                Button {
                    onSelect(tab)
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 19, weight: .medium))
                        Text(tab.label)
                            .font(.caption2.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .foregroundStyle(tab == selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(tab == selected ? .isSelected : [])
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 62)
        .modifier(GlassCapsule())
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
    }
}

private struct GlassCapsule: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: .capsule)
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        }
    }
}
