import Foundation

enum MemoriesSource: Equatable {
    /// Memories loaded straight from the server (Memories ≤ 8, or a manifest we can't verify).
    case direct(URL)
    /// Memories served by the local shell (Memories 9+), with Nextcloud's web root.
    case shell(URL, webRoot: String)
}

/// Owns the app's single local server and decides how Memories is loaded.
@MainActor
final class ShellHost {
    static let shared = ShellHost()

    let server = LocalServer()
    private var handler: LocalRequestHandler?

    /// The running shell's proxy, for native downloads.
    var proxy: UpstreamProxy? { handler?.proxy }

    /// HttpOnly, so scripts in the page can't read the secret.
    var authCookie: HTTPCookie? {
        HTTPCookie(properties: [
            .domain: "127.0.0.1",
            .path: "/",
            .name: LocalAuthGuard.cookieName,
            .value: server.authGuard.secret,
            HTTPCookiePropertyKey("HttpOnly"): "TRUE",
        ])
    }

    /// Returns the source and, when the shell couldn't be used, why.
    func prepare(_ credential: Credential) async throws -> (source: MemoriesSource, notice: String?) {
        let info = try await NextcloudAPI.describeMemories(credential)
        let direct = try info.entry(for: credential.server)
        guard let envelope = info.jsManifest else {
            await stop()
            return (.direct(direct), nil)
        }

        do {
            let assets = try SignedManifest.verify(envelope)
            let scriptBase = try await NextcloudAPI.memoriesScriptBase(credential, page: direct)
            let directory = try await AssetStore.appDefault().snapshot(for: assets, scriptBase: scriptBase)
            let entry = try await start(credential, info: info, assets: directory)
            return (.shell(entry, webRoot: info.webRoot), nil)
        } catch let error as ManifestError {
            await stop()
            return (.direct(direct), "Using Memories' web interface: \(error.localizedDescription)")
        } catch let error as AssetIntegrityError {
            await stop()
            return (.direct(direct), "Using Memories' web interface: \(error.localizedDescription)")
        } catch MemoriesError.scriptsNotFound {
            await stop()
            return (.direct(direct), "Using Memories' web interface: \(MemoriesError.scriptsNotFound.localizedDescription)")
        }
    }

    /// iOS closes the listening socket while the app is in the background.
    func resume() async throws {
        guard let handler, !(await server.isRunning) else { return }
        try await server.start(handler: handler)
    }

    func stop() async {
        handler = nil
        await server.stop()
    }

    private func start(_ credential: Credential, info: MemoriesInfo, assets: URL) async throws -> URL {
        let handler = LocalRequestHandler(
            authGuard: server.authGuard,
            assetDirectory: assets,
            proxy: try UpstreamProxy(credential: credential),
            shell: ShellConfig(info: info),
            localOrigin: server.origin
        )
        // Restart so a different account or Memories version takes effect.
        await server.stop()
        try await server.start(handler: handler)
        self.handler = handler

        let entryPath = LocalRouter(webRoot: info.webRoot).entryPath
        guard let entry = URL(string: server.origin.absoluteString + entryPath) else {
            throw ProxyError(reason: "invalid local entry path \(entryPath)")
        }
        return entry
    }
}
