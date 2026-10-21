# Sideloading test builds

Until the Apple Developer account exists, test builds are sideloaded with a free Apple ID through SideStore or AltStore. These re-sign the app for your own device. With a free Apple ID, apps expire after 7 days unless you refresh them, and you can have up to 3 sideloaded apps at once.

## How builds stay private

Every push to `main` builds an unsigned IPA and encrypts it with [age](https://github.com/FiloSottile/age) before uploading it as a workflow artifact.

- The workflow only has the public key, so GitHub stores no secret.
- The matching private key lives only on the maintainer's machine at `~/.config/cloudroll/ipa-key.txt`.
- Anyone can download the artifact, but it can't be decrypted without that key.
- `scripts/fetch-ipa.sh` deletes the fetched artifact, and any older unfetched ones, from GitHub right after decrypting. Artifacts that never get fetched expire after 1 day.

Back the key up somewhere safe. If it's lost, create a new one with `age-keygen` and put its public key into `IPA_RECIPIENT` in `.github/workflows/ios.yml`.

## Get the latest build

```sh
scripts/fetch-ipa.sh
```

The script:
- saves the build as `~/.cache/cloudroll/builds/Cloudroll-<version>-<timestamp>.ipa`, replacing older builds;
- uploads it to the `Cloudroll Builds` folder on Nextcloud (credentials in `~/.config/nc-keasbee.netrc`), deleting older IPAs there.

Each build gets a new name so the phone never opens a cached older copy. Builds are kept outside desktop-synced folders because sync clients can lag or skip rewritten files.

On the iPhone, open the IPA from the Nextcloud app (or Files) in SideStore, or install it over USB with [iloader](https://github.com/nab138/iloader).

Once the developer account exists, builds go out through TestFlight instead and this workflow step can be removed.
