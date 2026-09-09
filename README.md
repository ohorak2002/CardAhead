# Card Rewards Reminder

An iOS app that tells you which credit card to pay with, before you reach for
your phone.

Apple does not let a third-party app put anything into the Apple Pay double-tap
card picker. So the whole product hangs on arriving *early*: a local
notification fired by a geofence a few minutes after you walk in, not a
suggestion injected at the till.

## What is built

Build steps 1 to 3 of the plan, as agreed:

| Step | Status |
|---|---|
| 1. Data model — cards, categories, caps, rotating quarters | Done |
| 2. Wallet-style stacked card UI with add, expand, pin, reorder | Done |
| 3. Recommendation ranking engine, testable with no location | Done |
| 4. Region monitoring and the notification pipeline | Permission flow only |
| 5. Places API merchant resolution | Not started |
| 6. Significant-location-change travel mode | Not started |
| 7. Safari extension for online purchases | Not started |

Step 4 has its front half: `LocationAuthorization` walks Apple's
not-determined → When In Use → Always path and falls back to Settings once iOS
will not prompt again, and `LocationPrimerView` makes the case before the system
prompt appears. **No geofence is registered and no notification is sent yet** —
the permission is asked for and then not used.

Steps 5 and 7 have their data layer in place already —
`MerchantCategoryMap` maps both Google Places types and website domains onto the
same categories the engine ranks against — but nothing calls them yet.

## Layout

```
Packages/CardKit/       Pure Swift. No UIKit, no Core Location, no SwiftUI.
  Sources/CardKit/
    Models/             Card, CategoryRule, EarnCap, Quarter, WelcomeBonus, Perk
    Engine/             PurchaseContext, CardScore, RecommendationEngine
    Data/               CardCatalog (seed cards), MerchantCategoryMap
  Tests/CardKitTests/   The engine, exercised without a device
App/                    SwiftUI. The wallet stack, card detail, add flow.
project.yml             XcodeGen spec. The .xcodeproj is generated, not committed.
```

The split is the point. `CardKit` has no platform dependencies, so the ranking
logic runs under `swift test` in seconds and does not need a simulator, a
location fixture, or a notification permission.

## Running it

You need a Mac. Everything below assumes one.

Run just the engine and its tests — no Xcode project needed:

```bash
swift test --package-path Packages/CardKit
```

Build and run the app:

```bash
brew install xcodegen
xcodegen generate
open CardRewards.xcodeproj
```

CI runs both on every push, so the state of the build is visible from GitHub
rather than from someone's laptop.

## How the ranking actually works

The spec lists five ranking rules. Implemented literally they fight each other —
"highest earn rate" and "weight an open signup bonus heavily" cannot both be the
primary sort. So all of it is folded into **one number: cents earned per dollar
spent**, and only genuine ties fall through to tiebreaks.

1. **The best rate that actually applies.** A bonus whose cap is used up does
   not apply. A rotating bonus the user never activated does not apply. Both
   fall back to the base rate, and both say so in the caveats.
2. **Converted through the user's own point valuation.** 4x points at the
   default 1.0¢ is 4.0. Drop the valuation to 0.6¢ and a flat 3% cash back card
   correctly overtakes it. There is a test for exactly that.
3. **Minus a foreign transaction fee, when abroad.** A 3% fee on a 3% category
   is a wash, and the app should say so rather than cheerfully recommending it.
4. **Plus an open welcome bonus, spread across the spend still required.** $600
   of points with $3,000 left to earn them is 20¢ on the dollar, which
   *correctly* beats every category multiplier. This turns "weight it heavily"
   into arithmetic instead of a magic constant. Capped at 25¢/dollar so a bonus
   with one dollar left does not score in the thousands.
5. **Ties** break on pinned, then cap health, then travel perks while
   travelling, then annual fee, then name — so the order never jitters.

The notification names one card. Everything else — alternates, caveats, the
cap bars — appears only after a tap.

### The activation nudge

Chase Freedom and Discover both make you click a button each quarter, and people
forget. The engine checks whether an unactivated rotating bonus *would have won*,
and only then raises it. That is the one place the app tells you about a card it
is not recommending.

## Seeing it work before location exists

The wallet has a **Try it** button in the toolbar. Pick a category, a merchant
name, and the travelling/abroad toggles, and it renders the exact strings a
notification would carry plus the full ranking behind them. It is scaffolding
for this stage and moves behind a debug flag once step 4 lands.

## Decisions worth arguing with

**Card art is colour, not logos.** The spec asks for accurate replicas of the
real card art. Issuer logos and card designs are trademarked, and shipping pixel
copies needs a licence or issuer approval. `CardArt` uses each issuer's familiar
palette with a text wordmark instead. Recognition still works at a glance, and
swapping in licensed assets later touches one file.

**The seeded card data is a structure, not a source of truth.** The rates, caps,
and annual fees in `CardCatalog` model real, well-known card structures so the
engine has something realistic to rank. Issuers change all of it without notice.
Verify every figure against issuer terms before this goes anywhere near the App
Store.

**The rotating quarters are placeholders.** Issuers announce them one quarter at
a time, so a seed database cannot know them. The two quarters in `CardCatalog`
are stand-ins, and every card using them carries a note saying so. This needs a
real feed before step 4 is worth shipping.

**Cap spend is user-entered.** There is no transaction feed in v1 — that means
Plaid and a compliance surface, which the spec rules out. So the app cannot know
you have burned $6,000 of the grocery cap unless you tell it. The cap bars are
editable for that reason.

**Money is `Decimal`, rates are `Double`.** Dollar amounts and caps should not
drift; earn rates are ratios and never accumulate.

## What is deliberately absent

- No bank linking, no transaction data, no account.
- No network calls at all yet. The wallet is a JSON file in Application Support.
- No analytics.
