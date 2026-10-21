import Foundation
import Photos
import WebKit

/// Keeps the values Memories reads synchronously from `window.nativex` (media permission,
/// device folders) current inside the page, and tells the page when phone photos change.
@MainActor
final class PageState {
    static let shared = PageState()

    weak var webView: WKWebView?
    private var observer: LibraryObserver?

    /// Injected at document start; folders follow once the page has loaded.
    static var initialScript: String {
        "window.__cloudrollNative = { hasMediaPermission: \(PhotoLibrary.hasAccess), localFolders: '[]' };"
    }

    func push() async {
        let folders = await PhotoLibrary.shared.folders()
        do {
            let json = String(decoding: try JSONEncoder().encode(folders), as: UTF8.self)
            await evaluate("window.__cloudrollNative = { hasMediaPermission: \(PhotoLibrary.hasAccess), localFolders: \(ShellPage.jsString(json)) };")
        } catch {
            DiagnosticsLog.shared.add("native", "Encoding device folders failed: \(error.localizedDescription)")
        }
        observeLibraryIfAllowed()
    }

    /// Memories caches local days; it clears them on this event (src/native/days.ts).
    func libraryChanged() async {
        await PhotoLibrary.shared.invalidate()
        await evaluate("window._nc_event_bus?.emit('nativex:db:updated', null)")
    }

    /// The async API throws when a script's result can't be bridged (objects, undefined),
    /// so every script ends in a plain boolean.
    private func evaluate(_ script: String) async {
        guard let webView else { return }
        do {
            _ = try await webView.evaluateJavaScript(script + "; true")
        } catch {
            DiagnosticsLog.shared.add("native", "Updating the page failed: \(error.localizedDescription)")
        }
    }

    /// After access is first granted the timeline has to fetch days again.
    func reloadPage() {
        webView?.reload()
    }

    private func observeLibraryIfAllowed() {
        guard observer == nil, PhotoLibrary.hasAccess else { return }
        let observer = LibraryObserver()
        PHPhotoLibrary.shared().register(observer)
        self.observer = observer
    }
}

private final class LibraryObserver: NSObject, PHPhotoLibraryChangeObserver {
    func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in await PageState.shared.libraryChanged() }
    }
}
