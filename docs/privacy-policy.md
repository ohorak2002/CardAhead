# CardWise privacy policy — DRAFT

> **Draft for Oren to review, fill in and host.** Replace every `[bracket]`.
> Host it at a public https address (GitHub Pages works), put that address in
> App Store Connect *and* in the `PRIVACY_POLICY_URL` build setting, so More ›
> Privacy & legal links to it. This is not legal advice; if CardWise is ever
> offered in the EU/UK or California at scale, have it reviewed.
>
> Every sentence must stay true of the code. The in-app summary is
> `App/Views/PrivacyAndLegalView.swift`; the manifest is
> `App/PrivacyInfo.xcprivacy`. Change all three together.

**Effective date:** [date]
**Who we are:** CardWise is published by [your legal name or company],
[contact email].

## The short version

CardWise tells you which of your own credit cards is likely to earn the most
where you are. Your wallet lives on your iPhone. We have no servers that
receive your cards, and we never ask for a card number, security code, expiry
date or bank login.

## What stays on your iPhone

- The cards you add, their rewards rules, nicknames and any card photo you
  take. Photos are processed on the device to straighten them; CardWise does
  not read any text on the card.
- Your settings, point valuations and notification preferences.
- The list of places CardWise noticed you arriving at, and the history of
  which reminders it sent or held back (kept up to four days, 200 entries).
- Your Impact record: which reminders you said you used and any amounts you
  chose to type in.

None of this is uploaded. **Settings › Erase everything** deletes all of it,
and deleting the app deletes it too.

## What leaves your iPhone, and why

- **Your location, to Google.** To find shops near you — for the map and to
  choose which shops to watch for arrival reminders — CardWise sends your
  position (and anything you type into the map search) to the Google Places
  API. Nothing that identifies you is attached, but Google receives your
  device's IP address as with any web request. Google's handling is covered by
  its own privacy policy: https://policies.google.com/privacy. Place photos
  shown in the app are also fetched from Google.
- **What you type in the map's search box, to Apple.** Address suggestions
  come from Apple Maps, under Apple's privacy policy.
- **Opening a link** (a shop's website, directions, an issuer's terms page)
  hands you to Safari, Phone or Maps, which apply their own policies.

## Location permission

CardWise asks for **Always** location so that iOS can tell it when you arrive
at a shop while the app is closed. iOS does this with geofences (a circle
around up to 20 nearby shops) and significant-location-change updates, not
continuous GPS. You can use the wallet and map without Always, or with no
location at all. Arrival reminders need Always and Precise Location.

## Tracking, ads and analytics

CardWise has no advertising, does not track you across other companies' apps
or websites, and contains no analytics or crash-reporting service.

## Optional Impact sharing

[Keep this section only if a release build ships with the Impact sharing
service configured. If it does not, delete it.]

If you create an account and switch sharing on, CardWise uploads, per
recommendation: an event ID, the day, the card's catalog product ID, the
spending category, and dollar amounts you reported or the app estimated. It
does not upload shop names, locations, card photos or card numbers. Your
email is used only to sign in. Data is stored with Supabase ([region]) and
kept for [retention period]. You can stop sharing, delete shared records, and
delete your account at any time from within the app.

## Children

CardWise is not directed at children under 13 and does not knowingly collect
their information.

## Changes

We will update the effective date above and, for significant changes, say so
in the app's release notes.

## Contact

[contact email]
