# Roadmap

Cloudroll is free, with every feature included. It's funded by optional donations: an in-app tip jar, GitHub Sponsors and Ko-fi ([0006](decisions/0006-donations.md)). Tips unlock a few supporter app icons and nothing else.

## Phase 0: Foundations

- [x] CI build without a Mac (XcodeGen, GitHub Actions), with private sideload builds
- [x] Sign-in with Login Flow v2, app password in the Keychain ([0002](decisions/0002-sign-in.md))
- [x] Memories in a web view, opened at the server-reported base URL
- [x] Local Nextcloud 34 + Memories test server ([dev-server.md](dev-server.md))
- [x] **Step 1:** download Memories' signed web assets and verify them
- [x] **Step 2:** local server and the pass-through to Nextcloud ([0003](decisions/0003-local-server.md))
- [x] **Step 3:** serve the Memories page from the local server and switch the app to it (Memories 9+). Older servers keep using direct mode. ([0004](decisions/0004-shell-page.md)). Device-tested on 2026-10-21: thumbnails, video playback, resuming after suspension, staying signed in.

## Phase 1: Free version

- [x] Native Liquid Glass tab bar replacing Memories' bottom bar ([0005](decisions/0005-native-navigation.md))
- [x] Native Liquid Glass selection toolbar (Share straight to originals, Add to Album, Favorite with state, three-way Delete, More); hides over Memories' dialogs
- [x] **Step 4:** the `nativex` bridge, in parts (deleting and sharing phone photos landed with 4b; the timeline can show all photos, Nextcloud only or this iPhone only):
  - [x] **4a:** downloads and sharing through the iOS share sheet (`downloadFromUrl`, `SHARE_BLOBS`, `SHARE_URL`)
  - [x] **4b:** phone photos in the timeline (PhotoKit, permission and album choice, matched with server copies by `auid`/`buid`)
  - [x] **4c:** upload phone photos to Nextcloud (never overwrites), delete phone photos, three-way delete for photos on both
  - [x] **4d:** native Liquid Glass top bar replacing Memories' header (logo, upload, search)
- [x] In-app diagnostics log (long press on the tab bar) for device-only bugs
- [x] Native full-screen photo viewer v1: zoomable images, native video, swipe to page or close, glass controls (Share, Favorite, Add to Album, Delete); Memories' hidden viewer stays in charge of the current photo
- [x] Native viewer v2: info panel (button or swipe up), Live Photos (play on arrival, touch and hold, Live badge), editing through Memories' own editor, continuous swiping with the neighbouring photos loaded ahead

## Phase 2: More native features and support

- [x] Face ID app lock (Cloudroll settings: the gear on the timeline, or touch and hold the tab bar)
- [x] Editing phone photos: light and colour, filters, rotate and crop, saved through PhotoKit so Photos can revert it; Live Photos stay live
- [ ] Multiple servers or accounts
- [x] Batch save originals to Camera Roll (Save to Photos in the selection toolbar)
- [ ] Alternate app icons (a few unlocked by any tip)
- [ ] Tip jar (StoreKit 2 consumables) in Settings, plus a one-time ask after 30 days
- [ ] `FUNDING.yml` (GitHub Sponsors, Ko-fi) and a README Support section with costs and what donations paid for

## Phase 3: App Store

- [ ] Apple Developer Program enrollment (individual), TestFlight via fastlane
- [ ] Register the bundle ID (`app.cloudroll.ios` is a placeholder)
- [ ] Privacy policy (GitHub Pages) and privacy label ("Data not collected")
- [ ] Screenshots generated in the simulator, store listing, a demo account for Apple's reviewers
- [ ] Trademark: check the EU/TMview result, avoid Nextcloud and Memories logos, include a "not affiliated" line

## Phase 4: Updates

- [ ] Home screen widgets ("On this day", random photo)
- [ ] Offline albums served by the local server
- [ ] Shortcuts and Siri actions
