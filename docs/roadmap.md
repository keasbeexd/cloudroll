# Roadmap

Cloudroll ships as a free app with a one-time Pro unlock (~$2.99). Pro covers only native iPhone features. Nothing Memories offers free on the web goes behind the paywall.

## Phase 0: Foundations

- [x] CI build without a Mac (XcodeGen, GitHub Actions), with private sideload builds
- [x] Sign-in with Login Flow v2, app password in the Keychain ([0002](decisions/0002-sign-in.md))
- [x] Memories in a web view, opened at the server-reported base URL
- [x] Local Nextcloud 34 + Memories test server ([dev-server.md](dev-server.md))
- [x] **Step 1:** download Memories' signed web assets and verify them
- [x] **Step 2:** local server and the pass-through to Nextcloud ([0003](decisions/0003-local-server.md))
- [ ] **Step 3:** serve the Memories page from the local server and switch the app to it (Memories 9+). Older servers keep using direct mode.

## Phase 1: Free version

- [ ] **Native Liquid Glass navigation:** a SwiftUI tab bar (Timeline, Albums, Explore, Search) and a toolbar around the web content. Memories' own navigation is hidden with a stylesheet in the shell page. Tabs drive the Memories router, and the page reports its title and selection state so the toolbar shows the right actions (Share, Delete, Add to album).
  - Needs CI to build with Xcode 26 so the bars get Liquid Glass. iOS 17–25 show standard bars.
  - If a Memories release changes what the overrides depend on, the app falls back to the normal Memories interface. Check each Memories release against the test server.
- [ ] **Step 4:** the `nativex` bridge: phone photos in the timeline, the native share sheet, saving to Camera Roll, the native video player, uploading and deleting phone photos
- [ ] Native full-screen photo viewer with glass controls (swiping, pinch-zoom)

## Phase 2: Pro v1

- [ ] StoreKit 2 one-time unlock
- [ ] Face ID app lock
- [ ] Multiple servers or accounts
- [ ] Batch save originals to Camera Roll

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
