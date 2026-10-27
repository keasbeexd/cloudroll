import SwiftUI

/// Native Liquid Glass header for every Memories view: optional back button, the view's
/// title, and its actions. Search turns the bar into a glass search field; Upload opens a
/// native menu anchored under its button.
struct GlassTopBar: View {
    let title: String
    let showsBack: Bool
    let showsSearch: Bool
    let showsUpload: Bool
    let actions: [HeaderState.Action]
    let showsMore: Bool
    let onBack: () -> Void
    let onAction: (HeaderState.Action) -> Void
    let onMore: () -> Void
    let onSearch: (String) -> Void
    let onUpload: (UploadCenter.Source) -> Void
    /// Cloudroll's own settings, offered on the timeline.
    var onSettings: (() -> Void)?

    @State private var isSearching = false
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    var body: some View {
        Group {
            if isSearching {
                searchField
            } else {
                bar
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 2)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isSearching)
    }

    private var bar: some View {
        HStack(spacing: 10) {
            if showsBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 40, height: 40)
                }
                .foregroundStyle(.primary)
                .modifier(GlassBackground(shape: Circle()))
                .accessibilityLabel("Back")
            }
            if !title.isEmpty {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                    .padding(.horizontal, 16)
                    .frame(height: 40)
                    .modifier(GlassBackground(shape: Capsule()))
            }
            Spacer(minLength: 0)
            if hasTrailing {
                HStack(spacing: 0) {
                    if showsSearch {
                        iconButton("Search", "magnifyingglass") {
                            isSearching = true
                            searchFocused = true
                        }
                    }
                    if showsUpload {
                        uploadMenu
                    }
                    ForEach(actions.filter { !$0.isUpload }, id: \.self) { action in
                        iconButton(action.label, action.symbol) { onAction(action) }
                    }
                    if actions.contains(where: \.isUpload) && !showsUpload {
                        uploadMenu
                    }
                    if let onSettings {
                        iconButton("Cloudroll Settings", "gearshape", action: onSettings)
                    }
                    if showsMore {
                        iconButton("More", "ellipsis", action: onMore)
                    }
                }
                .padding(.horizontal, 4)
                .frame(height: 40)
                .modifier(GlassBackground(shape: Capsule()))
            }
        }
    }

    private var hasTrailing: Bool {
        showsSearch || showsUpload || !actions.isEmpty || showsMore || onSettings != nil
    }

    private var uploadMenu: some View {
        Menu {
            Button { onUpload(.photoLibrary) } label: { Label("Photo Library", systemImage: "photo.on.rectangle") }
            Button { onUpload(.camera) } label: { Label("Take Photo or Video", systemImage: "camera") }
            Button { onUpload(.files) } label: { Label("Choose Files", systemImage: "folder") }
        } label: {
            Image(systemName: "icloud.and.arrow.up")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 40)
                .contentShape(Rectangle())
        }
        .foregroundStyle(.primary)
        .accessibilityLabel("Upload")
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search your photos", text: $query)
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .textInputAutocapitalization(.never)
                    .onSubmit {
                        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        onSearch(trimmed)
                        isSearching = false
                    }
            }
            .padding(.horizontal, 14)
            .frame(height: 40)
            .modifier(GlassBackground(shape: Capsule()))
            Button("Cancel") {
                query = ""
                isSearching = false
            }
            .font(.body.weight(.medium))
            .padding(.horizontal, 14)
            .frame(height: 40)
            .modifier(GlassBackground(shape: Capsule()))
        }
    }

    private func iconButton(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
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
