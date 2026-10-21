# 0003: Local server with FlyingFox

Date: 2026-10-21

## Decision

The app runs an HTTP server on `127.0.0.1:47811` with [FlyingFox](https://github.com/swhitty/FlyingFox) 0.27.1 (MIT), pinned to that exact version in `config/project.yml`.

- **Access check:** every request must carry the `cloudroll_local` cookie, which holds 32 random bytes generated at launch and compared in constant time. Requests without it get 403.
- **`/local/assets/<name>`:** serves the asset snapshot verified by `AssetStore`. Other `/local/` paths return 404 and are never forwarded.
- **Everything else:** forwarded unchanged to the Nextcloud server's origin, with the app password as Basic auth. Before forwarding, the proxy drops the web view's Cookie, Authorization, Origin, Referer and hop-by-hop headers. Nextcloud's session cookies stay in the proxy's ephemeral URLSession, and `Set-Cookie` never reaches the web view. Redirects aren't followed. Instead, a `Location` header pointing at the server becomes a relative path, so the web view stays on the local origin.
- **Bodies:** responses stream through, so videos never sit in memory. Request bodies are buffered.
- **Port:** fixed, so the web view's origin and its local storage stay the same across launches.

## Why

- **Use a library:** any app on the device can connect to the port, so HTTP parsing is security-sensitive. FlyingFox is small, actively maintained, supports iOS, and handles any HTTP method, range requests and keep-alive.
- **Alternatives:** writing our own server on Network.framework would mean owning a hand-written HTTP parser. SwiftNIO/Hummingbird are much larger than this needs.
- **One origin:** the shell page, the proxied API and the `nativex` bridge share an origin, so the web UI needs no CORS and no Nextcloud cookie in the web view.

## Consequences

- iOS closes the listening socket when the app is suspended, so the server has to be restarted when the app returns to the foreground (`LocalServer.start` can be called again).
- The tests reach the server over real HTTP but stub Nextcloud with a `URLProtocol`. The test bundle doesn't link FlyingFox, to avoid loading a second copy into the test host.
- Large uploads are buffered in memory. If photo uploads from the phone need it, switch to streaming them from a file.
