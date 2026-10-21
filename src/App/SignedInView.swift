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
    @State private var reloadToken = UUID()

    var body: some View {
        content
            // Only the colour is mirrored: forcing a colour scheme here would also pin the
            // web view's prefers-color-scheme and stop Memories following the system.
            .background((themeColor ?? Color(.systemBackground)).ignoresSafeArea())
            .overlay(alignment: .bottom) { bottomOverlay }
            .task(id: reloadToken) { await prepare() }
            .task(id: toast) { await dismissToastLater() }
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
                onLoadError: { loadError = $0.localizedDescription },
                onSignOut: onSignOut,
                onBridgeMessage: handle
            )
            .id(reloadToken)
            .ignoresSafeArea(edges: .bottom)
        } else {
            VStack(spacing: 12) {
                ProgressView()
                Text("Preparing Memories…").foregroundStyle(.secondary)
            }
        }
    }

    private var bottomOverlay: some View {
        VStack(spacing: 8) {
            toastBanner
            if navigation.state.showsTabBar {
                GlassTabBar(
                    tabs: navigation.state.tabs,
                    selected: navigation.highlightedTab,
                    isCompact: navigation.state.collapsed == true,
                    onSelect: navigation.select,
                    onExpand: navigation.expand
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.25), value: navigation.state.showsTabBar)
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
        case .unsupported(let feature):
            toast = "\(feature) isn't available in Cloudroll yet."
        case .logout:
            onSignOut()
        case .navState(let state):
            navigation.update(state)
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
