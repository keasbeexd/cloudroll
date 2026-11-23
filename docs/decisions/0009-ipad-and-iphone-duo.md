# 0009: iPad and iPhone Duo

Date: 2026-11-23

## Decision

- Cloudroll is a universal app (`TARGETED_DEVICE_FAMILY` 1,2) from version 1.1. Before that it was iPhone-only and ran on iPads in iPhone compatibility mode.
- iPads get all four orientations, which Split View and Stage Manager require. The app keeps a single window (`UIApplicationSupportsMultipleScenes` false): the local server, page state and the upload and share centers exist once per app and can't serve two windows.
- Builds use Xcode 27.1 (iOS 27.1 SDK) on GitHub's `xcode-27` runner. With an older SDK, iPhone Duo shows the app at an iPhone aspect ratio in the middle of its inner display; with 27.1 it fills the display.
- Text that names the device says "iPad" on iPads ("Delete from This iPad Only"). `ThisDevice` reads the hardware model (`hw.machine`) instead of `UIDevice`, so the local server's threads can build those messages too. The Info.plist permission texts can't change at runtime and say "this device".

## Why

- iPad users reported that choosing an app icon failed. iOS on iPad looks up alternate icons in `CFBundleIcons~ipad`, and the asset compiler only writes that table for targets that include iPad. The iPhone-only build listed the alternates in `CFBundleIcons` alone. CI now fails if either table lacks the ten alternates.
- Apple's iPhone Duo guidance asks apps to size from their window rather than the screen, avoid device-idiom and orientation checks, and cope with bars moving. The code already follows it: no `UIScreen.main`, no idiom or orientation checks, windows come from scenes, and the viewer measures its own width (`onGeometryChange`). Cloudroll's tab bar and header are its own SwiftUI views, not system bars, so they don't turn vertical; they stay inside the safe area.

## Consequences

- The App Store needs 13-inch iPad screenshots for a universal app, and from April 2027 iPhone Duo screenshots for apps built with the iOS 27.1 SDK (outer display 1398 x 2034, inner 2007 x 2853). iPhone Duo screenshots before then add the "optimized for iPhone Duo" badge.
- The `xcode-27` runner only installs the iOS 27.1 simulator for iPhone Duo, so unit tests run on iPhone Duo. The screenshot workflow stays on `macos-26` for its iPhone 17 Pro Max and iPad simulators.
- Layout on iPad and iPhone Duo is checked by hand before release (glass bars, viewer, editor, settings sheets, split view sizes).
