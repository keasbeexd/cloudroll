# 0007: Multiple accounts by switching

Date: 2026-10-27

## Decision

- Cloudroll keeps any number of Nextcloud accounts, on one server or several, and shows one at a time. Settings has an Accounts section: tap an account to switch, swipe left (or touch and hold) to sign out, and Add Account runs the usual Login Flow v2 sign-in in a sheet. A merged timeline across accounts is out of scope.
- Each account is its own Keychain item (service `app.cloudroll.account`, keyed by the account's UUID, `AfterFirstUnlockThisDeviceOnly`). The order and the current account are in UserDefaults, since neither is secret. The single item from 0002 (`app.cloudroll.credential`/`current`) is migrated on first launch.
- Each account gets a persistent `WKWebsiteDataStore(forIdentifier:)` named by its UUID. The shell's origin (`127.0.0.1:` fixed port) is the same for every account, so a shared store would mix Memories' local storage and caches between them. A migrated install clears the default store once.
- Switching stops the local server and drops the native viewer's image cache and the Live Photo files, because both are keyed by shell URLs that repeat across accounts. The signed-in views are rebuilt from scratch.
- Which phone photos have a server copy (`localPhotos.hasRemote`) is stored per account. The album choice, timeline source, photo access and Face ID lock stay device-wide.
- Signing in again to an account that's already in the list keeps its id and data, replaces the app password and revokes the old one.
- Adding an account on a server that already has one uses an ephemeral browser session, so Safari's login for the first account isn't reused.
- Signing out deletes the Keychain item, empties the account's data store and revokes the app password. WebKit refuses to delete a store while a web view uses it, so stores without an account are deleted on the next launch, before any web view exists.
- The account list shows the Nextcloud display name (`ocs/v2.php/cloud/user`, read at sign-in) above `login@host`.

## Why

- Switching matches the Nextcloud iOS app and fits the architecture: Memories' web UI talks to one server, and the shell serves one account. A merged timeline would need a native timeline.
- Per-account data stores are the cheapest way to keep sessions apart without changing the shell's origin per account.

## Consequences

- Uploads already running keep going after a switch, because they talk to the server through the old account's proxy, not the local server.
- Existing users stay signed in after the update, but Memories' local settings and caches in the web view start fresh once.
