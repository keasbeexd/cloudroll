import SwiftUI
import UIKit

struct SignedInView: View {
    let account: Account
    let onSignOut: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppLock.self) private var lock
    @State private var source: MemoriesSource?
    @State private var loadError: String?
    @State private var toast: String?
    @State private var themeColor: Color?
    @State private var navigation = WebNavigation()
    @State private var selection = SelectionController()
    @State private var viewer = ViewerController()
    @State private var showsSettings = false
    @State private var showsTipAsk = false
    @State private var showsPhotoAccess = false
    @AppStorage("photoAccess.asked") private var askedForPhotoAccess = false
    @AppStorage(TimelineSource.storageKey) private var timelineSource = TimelineSource.all
    @State private var reloadToken = UUID()
    /// Offered once preparing takes a while, e.g. when the server is down.
    @State private var showsCancel = false
    @State private var cancelledToken: UUID?

    var body: some View {
        content
            // Only the colour is mirrored: forcing a colour scheme here would also pin the
            // web view's prefers-color-scheme and stop Memories following the system.
            .background((themeColor ?? Color(.systemBackground)).ignoresSafeArea())
            .overlay { viewerOverlay }
            .overlay(alignment: .bottom) { bottomOverlay }
            .overlay(alignment: .top) {
                topOverlay.animation(.smooth(duration: 0.25), value: showsTopBar)
            }
            .task(id: reloadToken) { await prepare() }
            .task(id: toast) { await dismissToastLater() }
            .sheet(isPresented: $showsSettings) {
                SettingsView(source: source)
            }
            .onChange(of: ShareCenter.shared.notice) { _, notice in
                guard let notice else { return }
                toast = notice
                ShareCenter.shared.clearNotice()
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
            .task(id: source) { await askForTipOnce() }
            .sheet(isPresented: $showsTipAsk) {
                NavigationStack {
                    TipJarView(onDismiss: { showsTipAsk = false })
                }
                .presentationDetents([.medium, .large])
            }
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
                    showsCancel = false
                    reloadToken = UUID()
                }
                Button("Settings") {
                    loadError = nil
                    showsSettings = true
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
                credential: account.credential,
                dataStore: AccountDataStore.store(for: account),
                navigation: navigation,
                selection: selection,
                viewer: viewer,
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
                if showsCancel && loadError == nil {
                    Text("Connecting to \(account.credential.server.host() ?? "your server")")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Cancel") {
                        cancelledToken = reloadToken
                        loadError = "Cloudroll stopped trying to reach \(account.credential.server.host() ?? "the server"). "
                            + "Check that it's online, then retry, or switch accounts in Settings."
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 8)
                }
            }
            .task(id: reloadToken) {
                guard (try? await Task.sleep(for: .seconds(5))) != nil else { return }
                withAnimation { showsCancel = true }
            }
        }
    }

    /// Native viewer over Memories' hidden one, in shell mode only.
    @ViewBuilder
    private var viewerOverlay: some View {
        if case .shell(let entry, let webRoot) = source,
           viewer.state.open,
           viewer.state.editing != true,
           let photo = viewer.state.photo,
           let origin = URL(string: "\(entry.scheme ?? "http")://\(entry.host ?? "127.0.0.1"):\(entry.port ?? 80)"),
           let media = ViewerMedia(photo: photo, origin: origin, webRoot: webRoot) {
            NativeViewer(
                photo: photo,
                media: media,
                previous: viewer.state.previous.flatMap { ViewerMedia(photo: $0, origin: origin, webRoot: webRoot) },
                next: viewer.state.next.flatMap { ViewerMedia(photo: $0, origin: origin, webRoot: webRoot) },
                cookie: "\(LocalAuthGuard.cookieName)=\(ShellHost.shared.server.authGuard.secret)",
                controller: viewer,
                onError: { toast = $0 }
            )
            .transition(.opacity)
        }
    }

    /// Shown on timeline-style views, hidden while scrolling down, selecting or in dialogs.
    /// Every view gets the glass header, except while scrolling down, selecting or in dialogs.
    private var showsTopBar: Bool {
        let state = navigation.state
        guard state.enabled, state.collapsed != true, !state.overlayOpen, !selection.state.active else { return false }
        return navigation.header.kind != "none" || !navigation.headerTitle.isEmpty
    }

    @ViewBuilder
    private var topOverlay: some View {
        if showsTopBar {
            let header = navigation.header
            GlassTopBar(
                title: navigation.headerTitle,
                // Views without a back button of their own (e.g. search results) go back in history.
                showsBack: header.back || (header.kind == "none" && navigation.currentTab == nil),
                showsSearch: header.kind == "timeline" || header.kind == "explore",
                showsUpload: header.kind == "timeline",
                actions: header.actions,
                showsMore: header.more,
                onBack: { navigation.headerBack() },
                onAction: { navigation.headerAction($0.icon) },
                onMore: { navigation.headerMore() },
                onSearch: { navigation.search($0) },
                onUpload: { source in Task { await upload(from: source) } },
                onSettings: header.kind == "timeline" ? { showsSettings = true } : nil
            )
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private var bottomOverlay: some View {
        VStack(spacing: 8) {
            if let busy = ShareCenter.shared.busyMessage ?? UploadCenter.shared.progress {
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
                        onLongPress: { showsSettings = true }
                    )
                    // Only the main timeline is filtered, so the switch lives on the Photos tab.
                    if navigation.currentTab?.href.hasSuffix("/") == true {
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
        .animation(.smooth(duration: 0.25), value: navigation.state.collapsed)
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
        let token = reloadToken
        await PhotoLibrary.shared.use(account: account.id)
        do {
            let prepared = try await ShellHost.shared.prepare(account.credential)
            // The user gave up on this attempt; a retry starts a new one.
            guard cancelledToken != token else { return }
            source = prepared.source
            toast = prepared.notice
        } catch is CancellationError {
            // The view went away or a retry started a new attempt.
        } catch {
            guard cancelledToken != token else { return }
            loadError = error.localizedDescription
        }
    }

    /// Once, 30 days after first use, and only when nothing else is going on.
    private func askForTipOnce() async {
        guard source != nil, TipJar.shared.shouldAsk else { return }
        // Let the timeline settle before asking.
        guard (try? await Task.sleep(for: .seconds(20))) != nil else { return }
        let busy = UploadCenter.shared.progress != nil
            || ShareCenter.shared.busyMessage != nil
            || DeleteChoiceCenter.shared.pendingCount != nil
            || viewer.state.open
            || selection.state.active
            || showsSettings
            || showsPhotoAccess
            || lock.isLocked
        guard !busy, scenePhase == .active else { return }
        TipJar.shared.markAsked()
        showsTipAsk = true
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
        case .viewer(let state):
            viewer.update(state)
        case .header(let state):
            navigation.update(state)
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

    private func upload(from source: UploadCenter.Source) async {
        let folder = HeaderState.folder(forPath: navigation.state.path)
        if let message = await UploadCenter.shared.upload(from: source, folder: folder) {
            toast = message
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
