# 0008: TestFlight uploads from GitHub Actions with Xcode cloud signing

Date: 2026-10-27

## Decision

- A separate, manually started workflow (`.github/workflows/testflight.yml`) archives a Release build and uploads it to App Store Connect. The push workflow keeps building the unsigned IPA for SideStore.
- Signing is cloud-managed: `xcodebuild -allowProvisioningUpdates` with an App Store Connect API key creates and renews the distribution certificate and profile. Nothing else is stored in the repository.
- Four repository secrets: `APPLE_TEAM_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID` and `ASC_KEY_P8` (the contents of the `.p8` file). The key needs the App Manager role.
- The build number is a UTC timestamp (`YYYYMMDDHHMM`), which always increases. The version is typed in when the workflow is started.

## Why

- No Mac: everything has to run on the macOS runner.
- Cloud signing avoids exporting a certificate and a provisioning profile into secrets and renewing them by hand every year. It replaces the fastlane plan in the roadmap; plain `xcodebuild` is enough and adds no Ruby setup.

## Setup after enrollment

1. Register the bundle ID `io.github.keasbeexd.cloudroll` (Certificates, IDs & Profiles) and create the app in App Store Connect with it.
2. In App Store Connect, Users and Access → Integrations → App Store Connect API, create a team key with the App Manager role. Download the `.p8` once; note the key ID and issuer ID.
3. Add the four secrets under the repository's Settings → Secrets and variables → Actions. The team ID is under Membership details in the developer account.
4. Run Actions → TestFlight → Run workflow.

## Consequences

- The first run may fail if the account still has an agreement to accept (Paid Apps agreement for tips) or no app record; App Store Connect shows what's missing.
- Revoking the API key stops uploads without touching anything else.
