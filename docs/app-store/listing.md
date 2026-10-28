# App Store listing (draft)

Paste into App Store Connect when the app record exists. Field limits are Apple's and are shown in brackets.

## App information

| Field | Value |
| --- | --- |
| Name (30) | Cloudroll |
| Subtitle (30) | Photos for your Nextcloud |
| Bundle ID | io.github.keasbeexd.cloudroll |
| Primary category | Photo & Video |
| Secondary category | Utilities |
| Age rating | 4+ (no objectionable content; users only see their own photos) |
| Price | Free |
| Copyright | 2026 followed by your legal name, typed in App Store Connect (Apple shows an individual seller's legal name anyway) |

## URLs

| Field | Value |
| --- | --- |
| Support URL | https://keasbeexd.github.io/cloudroll/support/ |
| Marketing URL | https://keasbeexd.github.io/cloudroll/ |
| Privacy policy URL | https://keasbeexd.github.io/cloudroll/privacy/ |

## Promotional text (170)

Your Nextcloud photos and the photos on your iPhone, together in one timeline, with a native viewer, Live Photos, editing and a Face ID lock.

## Description (4000)

Cloudroll is an iPhone app for Nextcloud Memories. It brings the photos on your own Nextcloud server and the photos on your iPhone together in one timeline, and adds the parts that should feel like iOS.

ONE TIMELINE
Photos on your iPhone show up next to the ones on your server. Upload what's missing, and delete from the phone, the server or both.

A PROPER PHOTO VIEWER
Pinch to zoom and swipe between photos. Swipe up for details and a map. Live Photos play the way they do in Photos.

EDIT ON YOUR PHONE
Adjust light and color, crop, rotate and add filters to photos on your iPhone. Edits are saved through Photos, so you can always revert them there.

SHARE AND SAVE
Send photos through the share sheet, or save originals from your server straight to your camera roll.

PRIVATE BY DESIGN
Cloudroll talks only to your own server. There are no ads, no analytics and no account with anyone else. Turn on Face ID and Cloudroll locks whenever you leave it.

MORE THAN ONE SERVER
Add your own Nextcloud, a family member's or a friend's, and switch between them in Settings.

WHAT YOU NEED
A Nextcloud server with the Memories app. Every feature needs Memories 9 or later (Nextcloud 34 or later). With older versions Cloudroll shows Memories' own web interface.

Cloudroll is free and open source. Tips in Settings are optional and help cover development costs.

Cloudroll is not affiliated with Nextcloud GmbH or the Memories project.

## Keywords (100)

nextcloud,memories,photos,gallery,self-hosted,photo backup,live photos,timeline,private cloud,album

## What's New (first version)

First release.

## App Privacy

- Data collection: **Data Not Collected**. Cloudroll talks only to servers the user adds; nothing reaches the developer.
- Tracking: No.
- The privacy policy URL above explains Apple Maps previews (location sent to Apple to draw a map) and Memories' own map tiles.

## In-app purchases

The three tips in [0006](../decisions/0006-donations.md#app-store-connect-setup). Display names: "Small tip", "Medium tip", "Large tip". Description for each: "A tip to support Cloudroll's development. It doesn't unlock anything."

## App Review information

- Sign-in required: yes. Provide a demo account on the Storage Share (Nextcloud 34, Memories 10) with a few sample photos, including one Live Photo and one photo with a location. Server address, user name and password go in the App Review fields, not in this file.
- Notes for the reviewer:
  > Cloudroll is a client for Nextcloud, a self-hosted cloud. To test it, enter the server address below on the first screen and sign in with the demo account in the browser sheet that opens (Nextcloud's own login page). After signing in, allow photo access to see the iPhone's photos in the same timeline. Tips are in Settings (gear icon on the timeline) and unlock nothing.
- Contact: the developer's own name, phone and email (App Store Connect keeps these private).

## Screenshots

Needed for 6.9" iPhone (1320 x 2868). Generate in the simulator on the CI macOS runner against the demo account once it exists. Suggested set: timeline with phone and server photos, the viewer with the info panel, a Live Photo, the editor, the accounts list in Settings.
