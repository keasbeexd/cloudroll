import SwiftUI
import UIKit

/// The app icons offered in Settings. Raw values name the asset catalog's sets
/// (`AppIcon-<name>`, `IconPreview-<name>`), rendered by scripts/render-icons.sh.
enum AppIcon: String, CaseIterable, Identifiable {
    case standard = "Default"
    case sunset = "Sunset"
    case sky = "Sky"
    case noir = "Noir"
    case lens = "Lens"
    case outline = "Outline"
    case film = "Film"
    case aperture = "Aperture"
    case goldenHour = "GoldenHour"
    case instant = "Instant"
    case grid = "Grid"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: "Cloudroll"
        case .goldenHour: "Golden Hour"
        default: rawValue
        }
    }

    /// The name iOS knows the icon by; nil is the main icon.
    var alternateName: String? {
        self == .standard ? nil : "AppIcon-\(rawValue)"
    }

    var previewName: String { "IconPreview-\(rawValue)" }

    @MainActor
    static var current: AppIcon {
        let name = UIApplication.shared.alternateIconName
        return allCases.first { $0.alternateName == name } ?? .standard
    }
}

/// A grid of the icons; iOS confirms the change with its own alert.
struct AppIconPicker: View {
    @Binding var selected: AppIcon
    @State private var errorMessage: String?

    private let columns = [GridItem(.adaptive(minimum: 76), spacing: 16)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(AppIcon.allCases) { icon in
                    Button { Task { await choose(icon) } } label: {
                        VStack(spacing: 8) {
                            AppIconImage(icon: icon, size: 64)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 64 * 0.225, style: .continuous)
                                        .stroke(Color.accentColor, lineWidth: selected == icon ? 3 : 0)
                                        .padding(-5)
                                }
                            Text(icon.title)
                                .font(.caption)
                                .foregroundStyle(selected == icon ? Color.primary : Color.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(icon.title)
                    .accessibilityAddTraits(selected == icon ? .isSelected : [])
                }
            }
            .padding(20)
        }
        .navigationTitle("App Icon")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Couldn't change the icon", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func choose(_ icon: AppIcon) async {
        guard icon != selected, UIApplication.shared.supportsAlternateIcons else { return }
        do {
            try await UIApplication.shared.setAlternateIconName(icon.alternateName)
            selected = icon
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// An icon's preview with the home screen's rounded corners.
struct AppIconImage: View {
    let icon: AppIcon
    let size: CGFloat

    var body: some View {
        Image(icon.previewName)
            .resizable()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
    }
}
