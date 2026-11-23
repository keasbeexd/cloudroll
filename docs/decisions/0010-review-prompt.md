# 0010: Asking for a rating

Date: 2026-11-23

## Decision

- Cloudroll asks for an App Store rating with the system prompt (StoreKit's `requestReview`), the one that reads "Enjoying Cloudroll?" with stars. There is no custom pre-prompt: guideline 5.6.1 requires the system API, and iOS decides whether the prompt appears, showing it at most three times a year.
- When: once per app version, after at least five visits to the timeline spread over at least a week since the first one. A visit is the timeline coming to the front (a new sign-in, a switch of account, or a return from the background).
- Never in the same visit as the one-time tip ask (0006), never while something is uploading, sharing, deleting, selecting, open in the viewer, in Settings or locked, and only after the timeline has been on screen for 20 seconds.
- Settings has a "Rate Cloudroll" row that opens the App Store's write-review page, for anyone who wants to rate without waiting.
- The counts (first visit, number of visits, last version asked) stay in UserDefaults on the device. Nothing is sent anywhere, so the privacy label stays "Data Not Collected".

## Why

- Ratings decide how a new app ranks in App Store search; most happy users never rate unless asked.
- Asking after real use, rarely, and never over something the user is doing keeps the prompt from being annoying.
