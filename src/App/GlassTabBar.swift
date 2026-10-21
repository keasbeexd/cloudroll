import SwiftUI

/// Floating tab bar in place of Memories' own. Liquid Glass on iOS 26; a blurred
/// material capsule on earlier versions. `shell-navigation.js` reserves 78px plus the
/// safe area below Memories' scrollers: this 62pt bar, its 8pt margin and an 8pt gap.
struct GlassTabBar: View {
    let tabs: [NavState.Tab]
    let selected: NavState.Tab?
    /// Shrinks to icons only while the user scrolls down, like iOS tab bars.
    let isCompact: Bool
    let onSelect: (NavState.Tab) -> Void
    let onExpand: () -> Void

    @Namespace private var selection
    @State private var taps: [String: Int] = [:]

    var body: some View {
        HStack(spacing: isCompact ? 2 : 0) {
            ForEach(tabs) { tab in
                button(for: tab)
            }
        }
        .padding(isCompact ? 5 : 6)
        .frame(height: isCompact ? 50 : 62)
        .modifier(GlassCapsule())
        .padding(.horizontal, isCompact ? 0 : 24)
        .padding(.bottom, 8)
        .animation(.spring(response: 0.38, dampingFraction: 0.78), value: selected)
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: isCompact)
        .sensoryFeedback(.selection, trigger: selected)
    }

    private func button(for tab: NavState.Tab) -> some View {
        let isSelected = tab == selected
        return Button {
            taps[tab.id, default: 0] += 1
            if isCompact && isSelected {
                onExpand()
            } else {
                onSelect(tab)
            }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: tab.symbol)
                    .font(.system(size: isCompact ? 17 : 19, weight: .semibold))
                    .symbolEffect(.bounce, value: taps[tab.id] ?? 0)
                if !isCompact {
                    Text(tab.label)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }
            .frame(maxWidth: isCompact ? nil : .infinity, maxHeight: .infinity)
            .frame(width: isCompact ? 46 : nil)
            .background {
                if isSelected {
                    Capsule()
                        .fill(.tint.opacity(0.16))
                        .matchedGeometryEffect(id: "selection", in: selection)
                }
            }
            .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
            .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(tab.label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Squishes slightly while pressed, like system tab bar items.
private struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
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
