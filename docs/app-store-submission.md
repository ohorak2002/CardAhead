# App Store submission checklist

Written 2026-09-23 during the release-readiness audit (PR #22). Guideline
numbers are Apple's App Review Guidelines as published on that date. Items
marked **code** are done in the repository; everything else is a manual step
in App Store Connect, Google Cloud, or on a real iPhone.

## Blockers — do these before submitting

1. **Privacy policy: hosted, and linked in the app.** It lives at
   https://ohorak2002.github.io/portfolio/cardahead/privacy/ and is linked
   from More › Privacy & legal (**code**). Still to do: paste that address
   into App Store Connect › App Privacy (5.1.1(i)).
2. **Support URL: hosted, and linked in the app.** It lives at
   https://ohorak2002.github.io/portfolio/cardahead/support/. Still to do:
   paste it into App Store Connect. The contact on both pages is
   CardAhead.help@outlook.com; use the same address as the App Store
   Connect contact email.
3. **Places key restricted and quota-capped.** In Google Cloud: API
   restriction = Places API (New) only; Application restriction = iOS apps,
   bundle ID `com.ohorak.cardrewards`; usage alerts at 2% of each daily
   quota (the daily quotas themselves are not adjustable on this account);
   a $10/month budget alert.
   The key ships inside the app, so restriction is the only protection.
   The app now sends `X-Ios-Bundle-Identifier` so this works (**code**).
   Validate on a device: build, open the Map, confirm places load. If the
   Map says "refused (403)", the bundle ID in the restriction does not match.
4. **An App Store build pipeline.** CI only makes an *unsigned* sideload
   `.ipa`. Submitting needs an Apple Developer Program membership, a
   distribution certificate and provisioning profile, and an archive
   uploaded with Xcode or Transporter (or a CI job with signing secrets).
   `DEVELOPMENT_TEAM` is empty in `project.yml`.
5. **Real-iPhone test pass** — see "Needs a physical device" below.
   Arrival reminders have never fired on a real phone.
6. **Leave `IMPACT_SERVICE_URL` / `IMPACT_PUBLIC_KEY` unset for 1.0.** If set,
   the app offers account creation, and 5.1.1(v) then requires in-app
   *account* deletion, which the app does not have (it can delete shared
   records but not the account). It would also need a review demo account
   (2.1) and more App Privacy answers. With them unset, the account screen is
   hidden (**code**).

## App Store Connect answers

**App Privacy ("nutrition label")** for a build with no Impact service:

| Data type | Collected? | Linked to user | Tracking | Purpose |
|---|---|---|---|---|
| Precise Location | Yes (sent to Google Places) | No | No | App Functionality |
| Everything else | No | — | — | — |

Being conservative on location is deliberate: the coordinate goes to a third
party whose retention CardAhead does not control. Search text typed into the
map also goes to Google/Apple for the real-time lookup only; Apple's
definition of "collect" excludes data used only to service a request in real
time, but if in doubt, add "Search History — not linked — App Functionality".

If the Impact service is ever turned on, add: Email Address, User ID,
Purchase History (volunteered amounts), Product Interaction — all linked,
purpose App Functionality/Analytics — and add the same to
`App/PrivacyInfo.xcprivacy`.

**Export compliance:** answered in the binary (`ITSAppUsesNonExemptEncryption
= false`, **code**). HTTPS and Keychain only.

**Age rating:** expected 4+. No user-generated content, no web browser
inside the app (links open Safari), no gambling, no mature content. Answer
"No" to everything; the questionnaire's "Unrestricted Web Access" is also No.

**Category:** Finance (primary) or Utilities. Finance invites closer review
of claims; see "Financial wording" below.

**Content rights:** say yes, you have the rights — the app ships no issuer
card artwork (`CardArtLibrary` is empty by design) and uses issuer names only
to identify cards.

**Review notes (paste and adapt):**
> CardAhead needs no account. Add a card from More or the Wallet's + button
> (e.g. search "Gold"). Location: the app asks for While Using, then Always,
> because arrival reminders are delivered by iOS geofences while the app is
> closed; the app works fully without location except for those reminders
> and the map. Reminders fire a few minutes after arriving at a shop where one
> of the user's cards earns a bonus, so they are hard to observe in review.
> CardAhead does not connect to banks and never reads card numbers.

Optionally attach a short screen recording of a reminder arriving.

## Screenshots and metadata

- Screenshots required for a 6.9" iPhone (1320×2868 or 1290×2796); Apple
  scales them down for smaller sizes. CI's simulator shots are the wrong size
  and include debug-only screens — take fresh ones.
- **No issuer card art in screenshots** — only the drawn cards the app ships.
  CLAUDE.md: in-app rights are not marketing rights.
- Metadata must not promise more than the app does (2.3.1). Avoid "save
  money", "maximize rewards guaranteed", "never miss a reward", or issuer
  names in the app name/subtitle/keywords (trademark, 2.3.7 / 5.2.1).
- Say "estimates" and "rewards", never "savings" (matches the app).

## Financial wording

- The app is informational, not a financial service: no money movement, no
  bank connection, no lending, no affiliate "apply now" links. That keeps it
  out of the 3.2.1(viii)/5.1.1(ix) "highly regulated field" bucket that must
  be submitted by an organisation. If affiliate links or bank connections are
  ever added, re-check that.
- In-app disclaimer (not financial advice, estimates, issuer terms decide,
  not affiliated) is in More › Privacy & legal (**code**). Consider a short
  version in the App Store description too.
- Card rates must stay current: `CardCatalog` goes stale after 180 days
  (`isStale`). Re-audit before submitting.

## Permissions (5.1.1, 5.1.5)

- Location: never asked at launch (**verified in code**). When In Use is
  asked the first time somebody opens the Map tab, or from the reminders
  primer; Always only from the primer, after its explanation. Strings
  updated to be accurate (**code**).
- No `UIBackgroundModes` location entry — region monitoring and significant
  change do not need one, and adding one would invite a 2.5.4 rejection.
- Camera: asked only on "Take a photo". Notifications: asked after location,
  from the primer or Settings.
- Approximate Location: reminders cannot work; the app now says so and points
  at Settings (**code**). Map still works.

## Accessibility (not an App Review gate, but checked)

- CI photographs every main screen at the largest Dynamic Type size and on a
  small iPhone; review those before submitting.
- Icon-only buttons scanned; none found without a label.
- Still to do on a device: a VoiceOver pass over Add Card, the wallet stack
  (drag to reorder has no VoiceOver alternative checked), the map pins.

## Needs a physical device

1. An arrival reminder actually firing (Always + Precise, walk into a watched
   shop, wait ~4 minutes). Also with the app force-quit.
2. Pick "Keep Only While Using" at the second prompt, then tap "Turn on
   reminders" again: it should open Settings (new behaviour).
3. Turn Precise Location off: Home/Wallet/Settings should say reminders
   cannot fire; turn it back on and the Watching count returns.
4. Restart the phone, don't unlock, walk into a watched shop, then unlock:
   cards and photos must all still be there (new load-failure guard).
5. The Places key with the iOS-app restriction on (see Blocker 3).
6. Notification badge image, haptics, camera + card-photo straightening.
