# Cloudroll

An iPhone app for [Memories](https://memories.gallery), the photo gallery app for Nextcloud. Not affiliated with Nextcloud GmbH or the Memories project.

## Status

Phase 0: the app loads Memories from your server in a web view. Native features come next. See [docs/decisions](docs/decisions).

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

## License

[MPL-2.0](LICENSE)
