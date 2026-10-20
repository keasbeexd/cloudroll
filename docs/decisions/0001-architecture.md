# 0001: Native shell around the Memories web UI

Date: 2026-10-20

## Decision

Cloudroll is a native SwiftUI app that shows the Memories web interface and plugs native features into it through Memories' existing `nativex` bridge, the same one the official Android app uses.

## Why

- Memories already has every gallery feature (timeline, map, faces, albums). Rebuilding them natively would take months, and the private Memories API they depend on changes between versions.
- The web UI turns on native mode only when `window.nativex` exists, so it has no Android-only check (`src/native/api.ts`).
- Since Memories 9, the Android app runs a local HTTP server on `127.0.0.1`. That server serves the web assets, which are downloaded from the user's server and checked against an Ed25519-signed manifest, and proxies everything else to Nextcloud, so the page and its native API share one origin. iOS allows the same design: an in-app listener on `127.0.0.1` with `NSAllowsLocalNetworking`. iOS cannot reproduce the older (Memories ≤ 8) design, which intercepted plain `http://127.0.0.1` requests from an https page.

## Consequences

- Native features (phone photos in the timeline, native sharing and video) need **Memories 9 or newer, which requires Nextcloud 34 or newer**. Older servers get the plain web UI only.
- No Memories code ships in the app. Memories is AGPL, and AGPL code can't go through the App Store. Web assets are downloaded from the user's own server at runtime.
- The Android app is AGPL. We read it to learn the bridge protocol, but we write our own implementation and never port its code line by line.
- The `nativex` API includes synchronous getters (e.g. `configGetLocalFolders`), while WKWebView's script messages are asynchronous. These values get injected into the page as a JavaScript cache that native code keeps up to date.
