# CardWise

An iOS app that tells you which credit card to pay with, before you reach for
your phone.

Apple does not let a third-party app put anything into the Apple Pay double-tap
card picker. So the whole product hangs on arriving *early*: a local
notification fired by a geofence a few minutes after you walk in, not a
suggestion injected at the till.

## What is built

| Step | Status |
|---|---|
| 1. Data model — cards, categories, caps, rotating quarters | Done |
| 2. Wallet-style stacked card UI with add, expand, pin, reorder | Done |
| 3. Recommendation ranking engine, testable with no location | Done |
| 4. Region monitoring and the notification pipeline | Built, not yet proven on a phone |
| 5. Places API merchant resolution | Done, needs an API key |
| 6. Significant-location-change travel mode | Not started |
| 7. Safari extension for online purchases | Not started |
| 8. Impact tracking — was any of this worth it | Local tracking plus opt-in sharing; backend deployment required |
| 9. Nearby Map — what is around you, and which card wins there | Built, needs an API key and a phone |

**Step 4** is written end to end. `RegionPlanner` picks the twenty nearest shops
your cards actually pay extra at, `RegionMonitor` registers them as
`CLCircularRegion`s and handles enter/exit, `ArrivalTracker` owns the
four-minute dwell rule, and `ReminderCenter` schedules the notification on
entry so it survives the app being suspended or killed. Leaving early cancels
it. None of that is *proven*: a unit test cannot show that a geofence wakes a
terminated app on a real iPhone. That needs a device.

It is also hardened against spamming you. `ReminderThrottle` caps it at one
reminder per shop and a handful in a day, both persisted so the limit survives
the app being killed. A win too small to matter — the best card barely beating
the next one — stays quiet. And editing or deleting a card while a reminder is
still in its four-minute wait actually changes what arrives: `walletDidChange()`
re-renders it against the wallet as it now stands, using the fact that iOS
replaces a pending notification under the same id rather than stacking a
second one.

**Step 9** is the one thing in the app you go and look at rather than being
told. Everything else answers "which card, here, now"; the Map tab answers
*where* — a search box, a radius, chips for restaurants, petrol, groceries,
shopping, malls, entertainment, hotels and everything else, a pin per place,
and under it a list saying which of your cards wins at each. Opening a place
gives you its hours, its phone number, directions, and the same ranking the
lock-screen reminder would have used, arrived at the same way.

It is careful about two things. It never invents a pin — with no Places key it
shows where you are and says plainly that it has nowhere to get shops from —
and it never invents a reward: a place whose type maps onto no earning
category says "no card in your wallet earns extra here" rather than guessing.
A ring around a pin means a card there beats its own everyday rate, which is
also the number Home counts when it says "3 opportunities nearby".

**Step 8** answers the question an app like this usually ducks: did being told
which card to use actually earn you anything? After a reminder, the wallet
shows one optional question — "did you use your Amex Gold?" — and a yes opens
one more, "roughly what did you spend?". Both are skippable and the app is
fully useful to somebody who never answers either.

What it reports is **not** savings. Nothing was discounted and no price
changed; these are rewards a purchase should earn, at a rate the app believed
applied and a point valuation you set yourself. And the headline figure is the
*incremental* one — what choosing that card is estimated to have earned over
the next best card you already hold — because a card paying 4x would have paid
4x whether or not anything told you about it. $85 of dining on a 4x card next
to a 2% card is $3.40 in points and **$1.70** of that attributable to being
told. See Settings > Your impact.

The ledger holds a spending category and never a merchant: no shop name, no
coordinate, no street. Switching the toggle off erases it, and so does Erase
everything.

**Step 5** calls Places API (New) `searchNearby` behind a cache — a 250m grid,
one week, forty squares, least-recently-used. The lookup happens when the
twenty-region plan is redrawn, never when a geofence fires, so the shop's name
and category are already in the registered region by the time you walk in. No
key is committed; without one the app runs, watches nothing, and says so in
Settings. See `docs/places-api.md`.

## September 2026 audit and personal rewards

Standard catalog terms, personal adjustments, and account-specific offers are stored separately. Benefits now compares rates within each reward currency; caps show reported usage or explicitly unknown usage. Add and manage offers from Benefits or card details. Map filters persist explicit All, None, or custom selection.

Impact remains useful locally without an account. Sharing is a separate opt-in, with offline retries and shared-record deletion. The native owner dashboard requires a deployed Supabase project and a verified account UUID provisioned server-side; no user becomes owner by signing up. See [backend setup](docs/impact-backend.md) and the [issuer audit](docs/card-data-audit-2026-09-20.md).

## Adding a card

You choose your card. You do not describe it.

1. Pick the bank.
2. Pick the exact product — "Gold" names more than one card, so the list shows
   the network, the annual fee and what the card is best at.
3. Confirm the benefits. They arrive already ticked, in plain English: *4x at
   restaurants*, *No foreign transaction fee*, *5% on this quarter's
   categories*. Untick anything your card does not have.

Nothing to type, no rate to look up, no cap to work out. A card that is not on
the list can still be described by hand, and it is ranked exactly the same way —
it just carries no source and no date, and the app says so instead of showing a
date it has not earned.

The wallet starts empty on a fresh install. Nothing is seeded and nothing is
imported: a card you did not add is a card whose rates you never checked.

## Layout

```
Packages/CardKit/       Pure Swift. No UIKit, no Core Location, no SwiftUI.
  Sources/CardKit/
    Models/             Card, CategoryRule, EarnCap, Quarter, WelcomeBonus,
                        Perk, CardBenefit, CardNetwork
    Engine/             PurchaseContext, CardScore, RecommendationEngine,
                        ArrivalReminder (the words on the lock screen)
    Data/               CardCatalog, MerchantCategoryMap, CardArtLibrary
    Geo/                RegionPlanner, ArrivalTracker, ReminderThrottle,
                        Merchant, MerchantSource, and the map's MapCategory,
                        MapPlace, MapFilter, NearbyPlaces
    Impact/             RecommendationSnapshot, BenefitEstimate, ImpactEvent,
                        ImpactLedger, AnalyticsService (legacy no-op), ImpactSharing
    Places/             GooglePlacesSource, MerchantCache, and the map's own
                        PlaceSearchSource / GooglePlaceSearchSource
  Tests/CardKitTests/   run on macOS and Linux
App/                    SwiftUI: the five tabs, the add flow, the map,
                        Core Location, and the notification centre
project.yml             XcodeGen spec. The .xcodeproj is generated, not committed.
```

The split is the point. `CardKit` has no platform dependencies, so the ranking
logic runs under `swift test` in seconds without a simulator, a location
fixture, or a notification permission — and it runs on Linux, which means it
runs in a browser tab through a Codespace.

## Running it

The engine and its tests need no Mac and no Xcode:

```bash
swift test --package-path Packages/CardKit
```

The app itself needs Apple's frameworks:

```bash
brew install xcodegen
xcodegen generate
open CardWise.xcodeproj
```

If you do not have a Mac, CI has one. Every push to `main` builds an unsigned
`.ipa` and uploads it as an artifact; Sideloadly on Windows signs it with a
personal Apple ID and installs it over a cable. See
`docs/testing-on-your-iphone.md`.

## How the ranking actually works

Five ranking rules implemented literally would fight each other — "highest earn
rate" and "weight an open signup bonus heavily" cannot both be the primary
sort. So all of it folds into **one number: cents earned per dollar spent**, and
only genuine ties fall through to tiebreaks.

1. **The best rate that actually applies.** A bonus whose cap is used up does
   not apply. A rotating bonus nobody activated does not apply. Both fall back
   to the base rate, and both say so.
2. **Converted through your own point valuation.** 4x points at the default 1¢
   is 4.0. Drop it to 0.6¢ and a flat 3% cash back card correctly overtakes it.
   There is a test for exactly that.
3. **Minus a foreign transaction fee, when abroad.** A 3% fee on a 3% category
   is a wash, and the app says so rather than cheerfully recommending it.
4. **Plus an open welcome bonus, spread across the spend still required.** $600
   of points with $3,000 left to earn them is 20¢ on the dollar, which
   *correctly* beats every category multiplier. Arithmetic instead of a magic
   constant, capped at 25¢ so a bonus with one dollar left does not score in the
   thousands.
5. **Ties** break on pinned, then cap health, then travel perks while
   travelling, then annual fee, then name — so the order never jitters.

The notification names one card. Alternates, caveats and cap bars appear only
after a tap.

### The activation nudge

Chase Freedom and Discover both make you click a button each quarter, and people
forget. The engine checks whether an unactivated rotating bonus *would have
won*, and only then raises it. That is the one place the app mentions a card it
is not recommending.

## Decisions worth arguing with

**Card art is never the bank's, unless the bank said yes.** Issuer card faces
are trademarked; Apple Wallet shows the real Amex front because Amex hands Apple
that image during provisioning, which is a business relationship rather than a
download. `CardArtLibrary` is the registry of artwork we hold a licence for, it
**ships empty on purpose**, and a test fails the build if that quietly changes.
`CardArtSource.resolve(for:)` is the only way to pick a face — licensed asset,
then your own photo, then a card CardWise draws itself at the real ISO/IEC 7810
proportion with a chip and a contactless mark and no logo. The app says in words
which of the three you are looking at.

A grant answers four separate questions and the app keeps them apart, because
collapsing any two is how an app ends up showing artwork it is not entitled to:
where the file came from, what state the grant is in (pending, approved,
revoked), what it covers (**permission to draw a card inside the app is not
permission to put it in an App Store screenshot**), and between which dates.
Every way that can go wrong — pending, revoked, lapsed, not started, wrong use,
a manifest missing a field, a manifest that will not parse, a deleted photo —
ends at the same place: CardWise draws the card. There is a test for each.

Photographing your own card is the exact-match route, and it stays on the
phone: found, flattened and cropped on device, never uploaded, never logged.
Nothing in that path reads the card — the only Vision request in the app finds
rectangles, and there is no OCR anywhere, because the app has never needed a
card number. See `docs/card-art.md`.

**Every number in the catalog cites the bank's own page and the day somebody
read it.** Not a review site: those are downstream of the same drift the field
exists to catch. Things the model cannot express are written down as prose in
`notModelled` rather than approximated into a rule, because an approximation
reads as a fact. The catalog goes stale after 180 days and the app starts saying
so rather than presenting old numbers as current.

**Rotating quarters are never invented.** Issuers announce them one quarter at a
time — Discover publishes a year ahead, Chase about a fortnight before the
quarter starts — so a shipped database physically cannot know them all.
`RotatingProgram.knownThrough` records how far the data actually goes, which
makes "this quarter pays nothing extra" and "nobody has published this quarter"
two different answers instead of one. Past the edge the app asks you, because
you got the email.

**Cap spend is user-entered.** There is no transaction feed in v1 — that means
Plaid and a compliance surface this app does not want. So it cannot know you
have burned $6,000 of the grocery cap unless you tell it, which is why the cap
bars are editable.

**Money is `Decimal`, rates are `Double`.** Dollar amounts and caps must not
drift; earn rates are ratios and never accumulate.

**The brand's own colours never touch a card face.** CardWise has an identity
— an icon, an accent colour, a Warning Yellow and Success Green off its own
palette — applied to buttons and status text throughout the app. `CardArt`,
the colours a *user* picks so their own card is recognisable in the stack, is
deliberately unrelated: a card that matched the app's own colour scheme
regardless of what you picked would stop being a way to tell cards apart. The
palette's neutrals are absent on purpose too — `.primary`/`.secondary` already
mean those roles and adapt to Dark Mode; hardcoding them would not.

**Removing a card asks no question — it offers Undo instead.** A six-second
banner, not a confirmation dialog: "Removed \[card\] — Undo." The card's photo
file survives past the removal so Undo restores the actual picture, and is
swept only once the window has genuinely closed.

## What is deliberately absent

- No bank linking, no transaction data, no account, no cloud.
- No analytics **sent anywhere**. The app keeps a local record of what its own
  reminders led to — see below — and ships `NoOpAnalyticsService`, which takes
  an event and drops it. There is no backend to send one to and no code that
  would.
- The wallet and the impact ledger are JSON files in Application Support. The
  only network call the app ever makes is an anonymous lookup of the shops near
  you.
