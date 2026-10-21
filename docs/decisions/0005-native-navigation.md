# 0005: Native Liquid Glass tab bar

Date: 2026-10-21

## Decision

In shell mode, Cloudroll replaces Memories' mobile bottom bar (`#mobile-nav`) with a native floating tab bar (`GlassTabBar`). It uses `glassEffect(.regular.interactive(), in: .capsule)` on iOS 26 and a material capsule on iOS 17–25.

`src/WebView/shell-navigation.js` ships as a bundle resource and is injected on `127.0.0.1` pages. It:

- does nothing unless `#mobile-nav` exists. When it does, it adds a stylesheet that hides the bar, lets the router outlet take the full height, and pads the timeline (`.recycler`) and grid (`.grid-recycler`) scrollers by `78px + env(safe-area-inset-bottom)`, so content scrolls under the glass but the last row stays reachable;
- reports `{enabled, tabs, path, hash}` whenever history, the fragment or the DOM changes, at most once per animation frame. Tab labels come from Memories' own (translated) links;
- exposes `__cloudrollSelectTab(href)`, which clicks Memories' hidden tab link, so Memories' own router logic runs.

The bar hides while an overlay is open. Memories encodes those in the URL fragment (`#v` viewer, `#s` selection, `#e` editor, `#m` modal, `#ss` settings, `#d` dialog, `#i` sidebar). Only `#day` keeps it visible.

## Why

- **A custom bar instead of `TabView`:** there's a single web view, and every tab is a route inside it. `TabView` expects a separate view per tab.
- **Clicking Memories' links:** rewriting the URL ourselves would bypass logic Memories runs on navigation.

## Consequences

- Memories' mobile header (logo, upload, search) stays for now, because upload lives there. It becomes a native top bar when uploading goes native (step 4).
- A native selection toolbar (Share, Delete, Add to album) needs Memories' internal selection state, so it's a separate, later piece. Until then Memories' own selection bar is used.
- If a Memories release renames `#mobile-nav` or the scroller classes, the script does nothing and Memories' own bar returns. Check each release against the test server.
