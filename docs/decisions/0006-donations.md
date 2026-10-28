# 0006: Donations instead of a Pro unlock

Date: 2026-10-26

## Decision

Cloudroll is free, with every feature included. The one-time Pro unlock planned in the first roadmap is dropped. Face ID lock, multiple servers, batch save, widgets and offline albums become ordinary features.

Support comes from donations through two channels:

- **In the app:** a tip jar using StoreKit 2 consumables at three sizes (around $1.99, $4.99 and $9.99). The jar is a "Support Cloudroll" row in Settings.
- **Outside the app:** GitHub Sponsors and Ko-fi, set once for every repository of the account in [`keasbeexd/.github`](https://github.com/keasbeexd/.github) (`.github/FUNDING.yml`) and linked from the README and the website. The app doesn't link to them.

Any tip unlocks a small set of supporter app icons. Every other icon stays free, and tips unlock nothing else. Apart from the Settings row, the app asks once: a dismissible line in the first "What's new" sheet after a user has used the app for 30 days. It never asks again, and never while something is uploading, being deleted or being shared.

The README gets a Support section with the yearly costs (the Apple Developer Program fee) and a short list of what donations have paid for, updated with releases.

## Why

- [openGym](https://github.com/DuarteSantos8/openGym), an AGPL self-hosted app also on the App Store, grew to about 16,000 stars with a plain promise: "free and stays free ... no paid tier, nothing held back for sponsors". Its donations go through Buy Me a Coffee, Ko-fi and GitHub Sponsors, linked from the README, FAQ and website. We follow the same promise.
- Self-hosters already pay for their own server and tend to dislike paywalls on an open-source client. A paid tier would also make it harder to accept community contributions.
- Tips in an app must use in-app purchase. In 2025 developers reported rejections under 3.1.1 for external "Tip" links, including in US-only apps, even after the US external-link change (3.1.1(a)). Keeping external links out of the app avoids that.
- Unlocking icons with a tip is allowed, because tips are in-app purchases.

## Consequences

- Phase 2 is reorganized: the former Pro features move to the free roadmap, and the tip jar is a separate small item.
- Consumable purchases don't show up in `Transaction.currentEntitlements`. The supporter icon flag is kept on the device (iCloud key-value store, so it survives a reinstall). Losing it is acceptable.
- In App Store Connect the tips are named and described as tips, with no promised content beyond the icons.
- Check the Review Guidelines again (3.1.1, 3.2.1) before submitting, because these rules have changed often since 2024.
