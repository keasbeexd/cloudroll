import Foundation

/// The synchronous half of Memories' native API (`NativeX` in Memories' src/native/api.ts),
/// injected as `window.nativex`. WKWebView messages are asynchronous, so getters answer
/// from fixed values and actions are posted to native code.
enum NativeBridgeScript {
    static let handlerName = "cloudroll"

    /// Video methods are deliberately missing so Memories keeps its web player until
    /// the native player exists.
    static let source = """
    (() => {
      if (location.hostname !== '127.0.0.1') return;
      const post = (method, ...args) =>
        window.webkit.messageHandlers.\(handlerName).postMessage({ method, args });
      window.nativex = {
        isNative: () => true,
        setThemeColor: (color, isDark) => post('setThemeColor', String(color), !!isDark),
        playTouchSound: () => {},
        vibrate: () => post('vibrate'),
        toast: (message) => post('toast', String(message)),
        logout: () => post('logout'),
        reload: () => location.reload(),
        downloadFromUrl: (url) => post('download', String(url)),
        setShareBlobs: (objects) => post('setShareBlobs', String(objects)),
        // Kept current by native code (PageState); getters must answer synchronously.
        configSetLocalFolders: (json) => post('setLocalFolders', String(json)),
        configGetLocalFolders: () => window.__cloudrollNative?.localFolders ?? '[]',
        configHasMediaPermission: () => !!window.__cloudrollNative?.hasMediaPermission,
        // PhotoKit needs no separate sync step, so indexing is always complete.
        getSyncStatus: () => -1,
        setHasRemote: (auids, buids, value) => post('setHasRemote', String(auids), String(buids), !!value),
      };
    })();
    """
}

enum BridgeMessage: Equatable {
    case setThemeColor(String, isDark: Bool)
    case vibrate
    case toast(String)
    case logout
    case navState(NavState)
    case download(String)
    case setShareBlobs(String)
    case log(level: String, message: String)
    case setLocalFolders(String)
    case selection(SelectionState)
    case viewer(ViewerState)
    case setHasRemote(auids: String, buids: String, value: Bool)

    /// Parses `{ method, args }` posted by the script; unknown shapes are rejected.
    init?(body: Any) {
        guard let dict = body as? [String: Any], let method = dict["method"] as? String else { return nil }
        let args = dict["args"] as? [Any] ?? []
        switch method {
        case "setThemeColor":
            guard let color = args.first as? String, let isDark = args.dropFirst().first as? Bool else { return nil }
            self = .setThemeColor(color, isDark: isDark)
        case "vibrate":
            self = .vibrate
        case "toast":
            guard let message = args.first as? String else { return nil }
            self = .toast(message)
        case "logout":
            self = .logout
        case "download":
            guard let url = args.first as? String else { return nil }
            self = .download(url)
        case "setShareBlobs":
            guard let json = args.first as? String else { return nil }
            self = .setShareBlobs(json)
        case "viewer":
            guard let json = args.first as? String,
                  let state = try? JSONDecoder().decode(ViewerState.self, from: Data(json.utf8))
            else { return nil }
            self = .viewer(state)
        case "selection":
            guard let json = args.first as? String,
                  let state = try? JSONDecoder().decode(SelectionState.self, from: Data(json.utf8))
            else { return nil }
            self = .selection(state)
        case "setLocalFolders":
            guard let json = args.first as? String else { return nil }
            self = .setLocalFolders(json)
        case "setHasRemote":
            guard args.count == 3, let auids = args[0] as? String, let buids = args[1] as? String,
                  let value = args[2] as? Bool
            else { return nil }
            self = .setHasRemote(auids: auids, buids: buids, value: value)
        case "log":
            guard let level = args.first as? String, let message = args.dropFirst().first as? String else { return nil }
            self = .log(level: level, message: message)
        case "navState":
            guard let json = args.first as? String,
                  let state = try? JSONDecoder().decode(NavState.self, from: Data(json.utf8))
            else { return nil }
            self = .navState(state)
        default:
            return nil
        }
    }
}
