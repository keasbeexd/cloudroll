# 0002: Sign-in with Login Flow v2 and a cookie session

Date: 2026-10-20

## Decision

- Sign-in uses Nextcloud Login Flow v2 in an `ASWebAuthenticationSession`. The app polls the flow's endpoint every 2 seconds and closes the sheet itself once it gets a credential, because the flow never redirects back to the app.
- The app password, login name and server go in the Keychain as one item (`AfterFirstUnlockThisDeviceOnly`, never synced).
- The web view opens Memories at the `baseUrl` reported by `api/describe`. The router only matches the address form the server generates (with or without `/index.php/`), so a hardcoded path left the first screen blank. The first request carries the app password once, as a Basic `Authorization` header. Nextcloud then sets a session cookie that covers every later request. We tested this against a Nextcloud 33 server on 2026-10-20.
- If the main frame is redirected to `/login`, the session has expired and the app signs in again. If that happens again within 10 seconds of sending the app password, the password was rejected, and the app shows an error instead of looping.
- Navigating to `/logout` signs the app out. Signing out deletes the Keychain item, clears website data and revokes the app password on the server (`DELETE /ocs/v2.php/core/apppassword`).

## Why

- With Login Flow v2, Nextcloud handles 2FA, SSO and password managers on its own page, so Cloudroll never sees the user's password.
- The browser sheet shares Safari's cookies, so a user already logged in there doesn't have to log in again.
- The app password sidesteps 2FA after sign-in, so the Keychain item stays on this device and gets revoked on sign-out.

## Consequences

- This is temporary until the local proxy (see 0001) arrives. Then the proxy attaches the credential to each upstream request, and the web view stops needing a Nextcloud session cookie.
