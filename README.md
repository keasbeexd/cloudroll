# Cloudroll

An iPhone app for [Memories](https://memories.gallery), the photo gallery app for Nextcloud. Not affiliated with Nextcloud GmbH or the Memories project.

Cloudroll is free and open source, with no ads and no tracking. It's supported by optional donations (see [Support](#support)).

## Status

In testing, not on the App Store yet. With Memories 9+ Cloudroll wraps Memories in native iOS controls:

- Your iPhone's photos in the timeline next to the ones on Nextcloud, with upload, delete (from the phone, Nextcloud or both), share and Save to Photos
- A native photo viewer with Live Photos, an info panel and smooth swiping
- Editing phone photos through PhotoKit, so the Photos app can revert the edit
- Liquid Glass navigation, Face ID lock, alternate app icons
- Several Nextcloud accounts, on one server or several

With older Memories versions it shows Memories' own web interface. See the [roadmap](docs/roadmap.md) and [design decisions](docs/decisions).

## Requirements

- iOS 17+
- Nextcloud with Memories installed. Native features will need Memories 9+, which requires Nextcloud 34+.

## Building

A Mac isn't needed. GitHub Actions builds every push (`.github/workflows/ios.yml`). To build on a Mac:

```sh
brew install xcodegen
xcodegen generate --spec config/project.yml --project .
open Cloudroll.xcodeproj
```

The Xcode project is generated from `config/project.yml` and isn't committed.

## Support

Donations are optional and help cover development costs and the hours that go into Cloudroll ([0006](docs/decisions/0006-donations.md)).

- In the app: the tip jar in Settings (coming with the App Store release)
- Outside the app: [GitHub Sponsors](https://github.com/sponsors/keasbeexd) or [Ko-fi](https://ko-fi.com/keasbeexd)

What it costs to run each year:

| Item | Cost |
| --- | --- |
| Apple Developer Program | US$99 |

What donations have paid for: nothing yet. This list is updated with each release.

## License

[MPL-2.0](LICENSE)
