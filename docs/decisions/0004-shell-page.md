# 0004: Memories shell page and the minimal bridge

Date: 2026-10-21

## Decision

When `api/describe?manifest=1` returns a signed manifest (Memories 9+) and it verifies, the app downloads the assets, starts the local server and opens `http://127.0.0.1:47811<webroot>/index.php/apps/memories/`. Otherwise, or if verification fails, it opens Memories directly from the server as before and shows why in a short message.

The local server generates the page Nextcloud would normally render:

- `<head data-user="…">` (read by `@nextcloud/auth`) and the server's stylesheets from `cssManifest`. The stylesheets load through the proxy, and only server-relative ones are accepted.
- One nonce'd inline script that sets `_oc_webroot`, `_oc_appswebroots` and `_oc_capabilities`, then the verified `memories-l10n.js` and `memories-main.js`.
- A strict Content-Security-Policy and `Cache-Control: no-store`.

Routing additions (`LocalRouter`):

- **The page:** HTML navigations to Memories app routes get the shell page. Memories' router base is `<webroot>/index.php/apps/memories` here, because the shell has no server config saying pretty URLs work.
- **Code chunks:** `…/apps/memories/js/<name>` comes from the verified snapshot.
- **Other HTML navigations:** these return 404 and are never forwarded. Remote HTML rendered on the local origin could reach the native bridge.
- **`/api`, `/image`, `/video`:** these go to the bridge. For now `/api/days` reports no phone photos, and everything else answers 501.

`window.nativex` is injected only on `127.0.0.1` pages. Its getters return fixed values. Its actions post to native code, which accepts messages only from the shell's main frame: theme colour, haptics, toast, logout. Downloads and sharing show a "not available yet" message. Video methods are left out, so Memories keeps its web player.

## Why

- Memories 9+ was built to run without Nextcloud's page in native mode. It needs only those globals, and the official Android app uses the same contract.
- Without `nativex`, Memories would run as if it were inside Nextcloud and skip its native setup (theme handling, browser checks).

## Consequences

- On Memories 8 servers (such as the maintainer's Storage Share until it moves to Nextcloud 34), the app keeps using direct mode.
- Downloads in shell mode wait for step 4, which adds a native download and the share sheet.
- The page depends on the globals Memories reads today. Check each Memories release against the test server.
