# 0004: Memories shell page and the minimal bridge

Date: 2026-10-21

## Decision

When `api/describe?manifest=1` returns a signed manifest (Memories 9+) and it verifies, the app downloads the assets by name from the folder the server really uses, read from `<script src="…/memories-main.js">` on the server's own Memories page. The manifest's hrefs hardcode `/apps/memories/js/`, but app store installs usually live in `/custom_apps/`, where those hrefs return 404. The app then starts the local server and opens `http://127.0.0.1:47811<webroot>/index.php/apps/memories/`. Otherwise, or if verification fails, it opens Memories directly from the server as before and shows why in a short message.

The local server generates the page Nextcloud would normally render:

- `<head data-user="…" data-requesttoken="…">` (read by `@nextcloud/auth`). The token is fetched through the proxy's cookie session, so Memories' first API call doesn't fail Nextcloud's CSRF check. Then the server's stylesheets from `cssManifest`. The stylesheets load through the proxy, and only server-relative ones are accepted.
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

## Verification

On 2026-10-21 a Python stand-in for these rules, run against the Nextcloud 34 test server in headless Chromium, booted Memories 10.1.0. It showed the first-run screen, then the timeline with its tabs, and every API call (config, days, previews) succeeded through the proxy. Headless Chromium never showed the thumbnails, so check thumbnails on a device.

## Consequences

- On Memories 8 servers (such as the maintainer's Storage Share until it moves to Nextcloud 34), the app keeps using direct mode.
- Downloads in shell mode wait for step 4, which adds a native download and the share sheet.
- The page depends on the globals Memories reads today. Check each Memories release against the test server.
