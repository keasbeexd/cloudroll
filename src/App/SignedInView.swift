import SwiftUI
import UIKit

struct SignedInView: View {
    let credential: Credential
    let onSignOut: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @State private var source: MemoriesSource?
    @State private var loadError: String?
    @State private var toast: String?
    @State private var themeColor: Color?
    @State private var navigation = WebNavigation()
    @State private var selection = SelectionController()
    @State private var showsDiagnostics = false
    @State private var showsPhotoAccess = false
    @AppStorage("photoAccess.asked") private var askedForPhotoAccess = false
    @AppStorage(TimelineSource.storageKey) private var timelineSource = TimelineSource.all
    @State private var reloadToken = UUID()

    var body: some View {
        content
            // Only the colour is mirrored: forcing a colour scheme here would also pin the
            // web view's prefers-color-scheme and stop Memories following the system.
            .background((themeColor ?? Color(.systemBackground)).ignoresSafeArea())
            .overlay(alignment: .bottom) { bottomOverlay }
            .task(id: reloadToken) { await prepare() }
            .task(id: toast) { await dismissToastLater() }
            .sheet(isPresented: $showsDiagnostics) {
                DiagnosticsView(source: source)
            }
            .sheet(isPresented: $showsPhotoAccess) {
                PhotoAccessView { allow in
                    showsPhotoAccess = false
                    askedForPhotoAccess = true
                    guard allow else { return }
                    Task { await grantPhotoAccess() }
                }
                .presentationDetents([.medium])
            }
            .task(id: source) { await offerPhotoAccess() }
            .confirmationDialog(
                deleteQuestion,
                isPresented: Binding(
                    get: { DeleteChoiceCenter.shared.pendingCount != nil },
                    set: { if !$0 { answerDelete(.cancel) } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete from This iPhone and Nextcloud", role: .destructive) { answerDelete(.both) }
                Button("Delete from Nextcloud Only", role: .destructive) { answerDelete(.cloudOnly) }
                Button("Delete from This iPhone Only", role: .destructive) { answerDelete(.phoneOnly) }
                Button("Cancel", role: .cancel) { answerDelete(.cancel) }
            }
            .onChange(of: timelineSource) {
                Task { await PageState.shared.refreshTimeline() }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active, case .shell = source else { return }
                Task { await resumeShell() }
            }
            .alert("Couldn't load Memories", isPresented: Binding(
                get: { loadError != nil },
                set: { if !$0 { loadError = nil } }
            )) {
                Button("Retry") {
                    loadError = nil
                    source = nil
                    reloadToken = UUID()
                }
                Button("Sign out", role: .destructive) {
                    loadError = nil
                    onSignOut()
                }
            } message: {
                Text(loadError ?? "")
            }
    }

    @ViewBuilder
    private var content: some View {
        if let source {
            MemoriesWebView(
                source: source,
                credential: credential,
                navigation: navigation,
                selection: selection,
                onLoadError: { loadError = $0.localizedDescription },
                onSignOut: onSignOut,
                onBridgeMessage: handle
            )
            .id(reloadToken)
            // Only the home-indicator area is ignored: the keyboard still shrinks the view,
            // so bottom sheets sit on top of it instead of WebKit panning the page.
            .ignoresSafeArea(.container, edges: .bottom)
        } else {
            VStack(spacing: 12) {
                ProgressView()
                Text("Preparing Memories…").foregroundStyle(.secondary)
            }
        }
    }

    private var bottomOverlay: some View {
        VStack(spacing: 8) {
            if let busy = ShareCenter.shared.busyMessage {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(busy).font(.callout)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .transition(.opacity)
            }
            toastBanner
            // Memories' dialogs (add to album, share, …) sit at the bottom; never cover them.
            if selection.state.active && !navigation.state.overlayOpen {
                SelectionToolbar(
                    label: selection.state.label,
                    allFavorite: selection.state.allFavorite == true,
                    onAction: { action in Task { await perform(action) } },
                    onMore: { Task { await selection.showMore() } },
                    onCancel: { Task { await selection.cancel() } }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if navigation.state.showsTabBar {
                HStack(spacing: 10) {
                    GlassTabBar(
                        tabs: navigation.state.tabs,
                        selected: navigation.highlightedTab,
                        isCompact: navigation.state.collapsed == true,
                        onSelect: navigation.select,
                        onExpand: navigation.expand,
                        onLongPress: { showsDiagnostics = true }
                    )
                    // Only the main timeline is filtered, so the switch lives on the Photos tab.
                    if navigation.highlightedTab?.href.hasSuffix("/") == true {
                        TimelineSourceButton(source: $timelineSource)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.horizontal, navigation.state.collapsed == true ? 0 : 16)
                .padding(.bottom, 8)
                .animation(.spring(response: 0.38, dampingFraction: 0.8), value: navigation.highlightedTab)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.25), value: navigation.state.showsTabBar)
        .animation(.smooth(duration: 0.25), value: selection.state.active)
    }

    @ViewBuilder
    private var toastBanner: some View {
        if let toast {
            Text(toast)
                .font(.callout)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, navigation.state.showsTabBar ? 0 : 32)
                .transition(.opacity)
        }
    }

    private func prepare() async {
        guard source == nil else { return }
        do {
            let prepared = try await ShellHost.shared.prepare(credential)
            source = prepared.source
            toast = prepared.notice
        } catch is CancellationError {
            // The view went away or a retry started a new attempt.
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func resumeShell() async {
        do {
            try await ShellHost.shared.resume()
        } catch {
            loadError = "The local Memories server couldn't restart: \(error.localizedDescription)"
        }
    }

    private func dismissToastLater() async {
        guard toast != nil else { return }
        do {
            try await Task.sleep(for: .seconds(3))
        } catch {
            return // A newer toast replaced this one.
        }
        withAnimation { toast = nil }
    }

    private func handle(_ message: BridgeMessage) {
        switch message {
        case .setThemeColor(let css, _):
            themeColor = Color(cssHex: css)
        case .vibrate:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .toast(let text):
            toast = text
        case .logout:
            onSignOut()
        case .navState(let state):
            navigation.update(state)
        case .selection(let state):
            selection.update(state)
        case .log(let level, let message):
            DiagnosticsLog.shared.add("page/\(level)", message)
        case .setLocalFolders(let json):
            Task { await setLocalFolders(json) }
        case .setHasRemote(let auids, let buids, let value):
            Task { await setHasRemote(auids: auids, buids: buids, value: value) }
        case .download(let href):
            Task { await download(href) }
        case .setShareBlobs(let json):
            do {
                try ShareCenter.shared.setPendingBlobs(json)
            } catch {
                toast = error.localizedDescription
            }
        }
    }

    private var deleteQuestion: String {
        let count = DeleteChoiceCenter.shared.pendingCount ?? 0
        return count == 1
            ? "This photo is on this iPhone and on Nextcloud."
            : "\(count) of these photos are on this iPhone and on Nextcloud."
    }

    private func answerDelete(_ choice: DeleteChoice) {
        guard DeleteChoiceCenter.shared.pendingCount != nil else { return }
        DeleteChoiceCenter.shared.answer(choice)
        // Memories stops its flow for these, leaving the photos selected.
        if choice == .phoneOnly || choice == .cancel {
            Task { await selection.cancel() }
        }
    }

    private func perform(_ action: SelectionController.Action) async {
        guard await selection.perform(action) else {
            toast = "\(action.title) isn't available here."
            return
        }
    }

    /// Asked once, after Memories has loaded from the local shell.
    private func offerPhotoAccess() async {
        guard case .shell = source, !askedForPhotoAccess, PhotoLibrary.isUndetermined else { return }
        do {
            try await Task.sleep(for: .seconds(1.5))
        } catch {
            return // The view changed before the prompt was due.
        }
        showsPhotoAccess = true
    }

    private func grantPhotoAccess() async {
        guard await PhotoLibrary.shared.requestAccess() else { return }
        await PageState.shared.push()
        // The timeline already loaded without phone photos.
        PageState.shared.reloadPage()
    }

    private func setLocalFolders(_ json: String) async {
        do {
            let folders = try JSONDecoder().decode([LocalFolder].self, from: Data(json.utf8))
            await PhotoLibrary.shared.setFolders(folders)
            await PageState.shared.push()
            await PageState.shared.libraryChanged()
        } catch {
            toast = "Couldn't save the album choice: \(error.localizedDescription)"
        }
    }

    private func setHasRemote(auids: String, buids: String, value: Bool) async {
        do {
            let decode = { (json: String) in try JSONDecoder().decode([String].self, from: Data(json.utf8)) }
            await PhotoLibrary.shared.setHasRemote(auids: try decode(auids), buids: try decode(buids), value: value)
        } catch {
            DiagnosticsLog.shared.add("native", "Memories sent unreadable backup markers: \(error.localizedDescription)")
        }
    }

    private func download(_ href: String) async {
        guard let proxy = ShellHost.shared.proxy else {
            toast = "Downloading needs the local Memories server, which isn't running."
            return
        }
        do {
            try await ShareCenter.shared.download(href, using: proxy, localOrigin: ShellHost.shared.server.origin)
        } catch {
            toast = error.localizedDescription
        }
    }
}

extension Color {
    /// Parses "#rgb" or "#rrggbb", the forms Nextcloud's theme variables use.
    init?(cssHex value: String) {
        var hex = value.trimmingCharacters(in: .whitespaces)
        guard hex.hasPrefix("#") else { return nil }
        hex.removeFirst()
        if hex.count == 3 {
            hex = hex.map { "\($0)\($0)" }.joined()
        }
        guard hex.count == 6, let rgb = UInt32(hex, radix: 16) else { return nil }
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}
