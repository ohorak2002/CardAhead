# Working notes for this repo

Orientation for whoever (human or Claude) picks this up next. The README is
for people evaluating the project; this file is for people about to edit it.

## The one fact that shapes everything else

**Development happens on Windows. There is no Swift toolchain on this
machine.** Nothing Swift can be compiled or tested locally. The only way to
know whether Swift code works is to push and read CI.

- `swift test --package-path Packages/CardKit` runs on **macOS and Linux** in
  CI (`.github/workflows/ci.yml`) — CardKit is Foundation-only, so it builds
  on both.
- CI's `ipa` job is also the only route onto a real iPhone, because Xcode is
  macOS-only and the dev machine is not. It archives unsigned and uploads an
  `.ipa` artifact; Sideloadly on Windows signs it with a personal Apple ID and
  installs it over a cable. See `docs/testing-on-your-iphone.md`.
- The full iOS app only builds on the **macOS** job (`xcodegen generate` +
  `xcodebuild`), because SwiftUI needs Apple's frameworks.
- **Never claim Swift code works before CI is green.** Push, watch the run,
  report what actually happened — not what the diff looks like it should do.
- A GitHub Codespace (`swift test`) is the fastest way for a human to run the
  real engine from a browser, without a Mac.

## There is no web preview any more

A `which-card-wins.html` Artifact used to hand-mirror the SwiftUI app so the
work could be seen on Windows. **It is retired. Do not rebuild it, and do not
maintain one.** This is an iOS app; a JS twin is a second implementation of
every feature, it drifted from the Swift once already, and keeping it in step
cost more than it showed. Build in `App/` and `Packages/CardKit/` only.

The consequence is that nothing is visually verifiable before CI. That is the
trade, and it is the user's call.

## Architecture

```
Packages/CardKit/       Pure Swift. No UIKit, no Core Location, no SwiftUI.
  Sources/CardKit/
    Models/             Card, CategoryRule, EarnCap, Quarter, WelcomeBonus,
                         Perk, CardFinish, CardBenefit (the user-facing
                         benefits layer), CardNetwork
    Engine/             PurchaseContext, CardScore, RecommendationEngine
    Data/               CardCatalog (seed cards), MerchantCategoryMap,
                         CardArtLibrary (licensed card art registry)
    Geo/                GeoCoordinate, Merchant, RegionPlanner (which 20
                         places to watch), ArrivalTracker (the dwell rule),
                         ReminderThrottle (daily/per-merchant limits),
                         MerchantSource. And the map's own four:
                         MapCategory (what kind of shop), MapPlace (a pin,
                         with an optional earning category), MapFilter +
                         NearbyPlaces (filter, measure, rank, order),
                         MapCluster (pins that would overlap, and the
                         RegionPlan.watchedPlaceIDs join)
    Engine/ArrivalReminder.swift   the words on the lock screen, and the
                         ArrivalDecision that carries either those words or
                         the reason there were none
    Impact/             RecommendationSnapshot (the numbers frozen at the
                         till), BenefitEstimate + BenefitValueCalculator,
                         ImpactEvent, ImpactLedger, AnalyticsService (a
                         no-op — there is no backend and no network call)
    Places/             GooglePlacesSource, MerchantCache, and an HTTPRequest
                         value type so no URLSession enters this package.
                         PlaceSearchSource + GooglePlaceSearchSource +
                         MapPlaceCache are the map's half: a different
                         question, a different field mask, a different cache
  Tests/CardKitTests/    run on both macOS and Linux CI
App/
  Models/ (none — CardKit owns them)
  Store/WalletStore.swift        wallet CRUD, photo storage, JSON persistence
  Store/ImpactStore.swift        the on-device ledger of what reminders led to
  Store/NearbyPlacesStore.swift  the Map tab's state: centre, filter, results,
                         and the one thing that went wrong. Foreground only
  Location/LocationAuthorization.swift   the permission ladder
  Location/RegionMonitor.swift           CLCircularRegion plumbing only
  Location/ArrivalNotifier.swift         seam between arriving and being told
  Notifications/ReminderCenter.swift     UNUserNotificationCenter, both ends
  Places/PlacesProvider.swift            URLSession, and the API key or not.
                         Vends two sources off one key: makeSource() for
                         geofences, makePlaceSearchSource() for the map
  Theme/CardWiseColor.swift              the brand palette, chrome only —
                         never a card face; see CardArt below
  Theme/CardWiseStyle.swift              the design system: Metric (8pt grid),
                         the two gradients, per-category tint and symbol, and
                         the shared pieces (CategoryIcon, StatTile, TagPill,
                         SectionHeader, .cardWisePanel())
  Store/DemoSeed.swift                   debug-only seeded wallet, so CI can
                         photograph screens with something on them
  Theme/CardArt.swift                    the colours a *user* picks for a
                         card face; deliberately unrelated to the brand
  CardPhoto/CardPhotoProcessor.swift     find the card's corners, flatten the
                         perspective, crop to 1.586:1. Rectangles only — no
                         OCR, ever
  CardPhoto/CameraPicker.swift           UIImagePickerController, presented on
                         a tap and nowhere near launch
  Assets.xcassets/                       AppIcon (single 1024px), AccentColor,
                         CardWiseSuccess/Warning/Error color sets
  Views/                         see below. AddCardView + CardBenefitsView
                         are the add flow; CardEditorView is the way out
project.yml             XcodeGen spec. The .xcodeproj is generated, not
                         committed — run `xcodegen generate` after cloning.
docs/card-art.md         runbook for adding a licensed card-art asset
docs/places-api.md       runbook for the Places key
docs/testing-on-your-iphone.md   the all-Windows route onto a real device
```

The `CardKit` / `App` split is deliberate and load-bearing: `CardKit` has zero
platform dependencies, so the ranking logic is testable on Linux CI in
seconds. Keep it that way — no SwiftUI, no UIKit, no Core Location imports in
`Packages/CardKit`.

## The app's five tabs

`RootTabView` is the shell. **This replaced a single-screen app on purpose,
and kept the reason that app was single-screen.** The wallet used to be
everything, deliberately holding only cards, because a screen with two
subjects on it is a screen nobody reads. That principle is intact — the Wallet
tab is *still* nothing but cards. What changed is that everything else had
grown a tail of bars and sheets hanging off the bottom of it, and a tab bar is
the Apple answer to that.

**This said "four tabs, not five: five reads as a menu" until the Map tab was
added.** That rule was right and the exception was taken deliberately, not
forgotten: Map is the only screen that answers *where* rather than *which
card, here, now*, it needs a map's whole vocabulary (a radius, a kind of
shop, a search box), and every place it could have been hung off would have
made it a tail on another screen — which is the exact thing the tab bar
existed to stop. **Five is now the ceiling, not the new number.** The next
thing goes inside More, the way Impact did.

1. **Home** (`HomeView`) — a navy gradient header, what the app is doing right
   now, up to two things worth doing, and a horizontal peek at the wallet.
   Every line on it is derived from something real; see its doc comment for
   the list. It must never claim to have found opportunities it has not.
2. **Map** (`NearbyMapView`) — the Nearby Map: search box, category chips, a
   distance, a MapKit map with a pin per place, and a list underneath saying
   which card wins at each. Pins that would overlap are drawn as one carrying
   a count (`NearbyPlaces.pinGroups`), and tapping it zooms until they come
   apart. A bell on a pin or a row means that shop already has a geofence, and
   the **Watching** chip shows only those — read out of the region plan
   itself, not filtered from the map's results.
   `NearbyPlacesStore` owns the state; everything that could be *wrong* about
   it is in CardKit (`NearbyPlaces.results`, `pinGroups`) and tested on Linux.
   `MapFiltersView` is the sheet, `MapSettingsView` the standing preferences
   under Settings, `PlaceDetailView` one place opened.
3. **Wallet** (`WalletStackView`) — the stack, and a plus. Nothing else. It no
   longer owns a `NavigationStack` (the tab does) and no longer carries the
   settings gear or the "Why this card" bar.
4. **Benefits** (`BenefitsBrowserView`) — the wallet's benefits by shelf, not
   by card, over `WalletInsights.benefitGroups`. A two-column grid of category
   tiles, a filter, and a "Running out" list.
5. **More** (`MoreView`) — Your impact (`ImpactView`), Why this card
   (`WhyThisCardView`), Settings (`SettingsView`).

Adding a card is a sheet, not a tab of its own, and it is three steps:
`AddCardView` (bank, or search) -> the bank's products -> `CardBenefitsView`
(confirm what it is good for), where "this is the wrong card" and "correct the
details myself" also live. `CardEditorView` is reached only from "my card is
not on the list" and from that screen; it is not on the plus button and must
not go back there.

## Conventions established this session

- **A fresh wallet starts empty. Never preload cards.** `CardCatalog` is the
  list the add flow *searches*, never a seeded starter wallet. `WalletStore`'s
  doc comment states this explicitly — read it before touching `init`/`load`.
- **Confirmation dialogs go on destructive, irreversible actions — not on
  easily-undone ones.** Early in the session a confirm dialog was added to
  "prefer this card" (a harmless, instantly-reversible tiebreak toggle) while
  "Remove" (permanent, no undo) had none. This was flagged in the Apple-design
  audit as backwards and partially fixed (Erase-everything now confirms;
  Remove still doesn't — see Pending).
- **Editing a card is applied onto the original, never rebuilt from the
  form.** `CardEditorView`'s form only owns six fields (name, look, material,
  earn rules, fees, photo). Cap spend, the rotating programme, perks, notes, an
  open signup bonus, and the pin must all survive an edit untouched. See
  `CardEditorView.apply(to:)` and its doc comment — this is the trap to avoid
  if this view is ever rewritten.
- **Point valuation lives on the currency (`RewardCurrency.name`), not the
  card.** Someone holding two Chase cards states what a Chase point is worth
  once, in Settings, not per-card.
- **Money is `Decimal`; earn rates are `Double`.** Dollar amounts and caps
  must not drift; rates are ratios that never accumulate.
- **New `Card` fields are optional with a sensible default accessor**
  (`finish: CardFinish?` + `var appearance: CardFinish { finish ?? .matte }`).
  A wallet JSON file written before a field existed must still decode.
- **Never add issuer card artwork from an internet search, an issuer website
  screenshot, a comparison site, a press kit, a social media post, or any other
  source, unless this repository contains documented permission appropriate for
  the intended use.** And **never use AI-generated artwork to reproduce an
  unlicensed issuer's card design** — not a copy, not a recolour, not the same
  composition with the logo taken off. Generative models are not a licensing
  workaround. If the permission is not in writing and cannot be produced on
  request, the app draws its own card, and that is a perfectly good outcome.
- **Issuer card art is never shipped without a recorded licence.**
  `CardArtLibrary.assets` ships empty on purpose, with a test
  (`testLibraryShipsEmpty`) asserting it stays empty until someone deliberately
  adds an entry per `docs/card-art.md`. `CardArtSource.resolve(for:)` is the
  only way to pick a face: licensed asset → user's own photo → drawn card.
  Never bypass this to hardcode an issuer's logo/art.
- **Four questions about a licence, kept apart on purpose.** Where the file came
  from (`ArtLicence`), what state the grant is in (`ArtLicenceStatus`), what it
  covers (`ArtUse`), and when (`effectiveDate`/`expiresOn`). Collapsing any two
  is how an app ends up showing artwork it is not entitled to, and the two that
  most want collapsing are the middle pair: **provenance is not permission**
  (an asset the issuer definitely emailed us is still refused while its status
  says pending), and **in-app rights are not marketing rights** (a grant to draw
  a card in the wallet is not a grant to put it in an App Store screenshot).
  `CardArtAsset.isUsable(for:asOf:)` is the single gate; nothing forms its own
  opinion. There is deliberately no `.expired` status — that is arithmetic on
  `expiresOn`, not a state somebody has to remember to update.
- **Everything in the art path fails towards the drawn card**, and the tests
  assert each row of that table (`docs/card-art.md`). A manifest missing its
  status reads as `pendingReview`, missing its uses as none, malformed as
  refused. If you change this system and have to choose, choose the direction
  where a bug loses a licensed image rather than one where a bug shows an
  unlicensed one.
- **Artwork is keyed on `catalogProductID`, never on issuer + name.** Matching
  on display strings meant a card typed in by hand as "Amex"/"Gold" picked up a
  grant written for the catalog product, and an issuer renaming a card silently
  lost its artwork — the exact thing product ids exist to prevent. A card with
  no product id therefore never matches a grant, which is the safe answer.
  `CardArtLibrary.match(productID:in:)` and `CardArtSource.resolve(for:in:)`
  take an explicit list so these rules can be tested against a registry that is
  not the (empty) shipping one. **They are internal, and must stay internal** —
  a public overload would be a way around the registry.
- **Nothing in the card-photo path reads the card.** The only Vision request in
  the app is `VNDetectRectanglesRequest`, which finds quadrilaterals.
  No OCR, no text recognition, and no code that extracts a card number,
  security code or expiry date — the app has never needed them, and a card
  photo is the most sensitive thing a user hands this app. Photos are never
  uploaded, never logged, never sent to analytics or a crash reporter.
  `CardPhotoProcessor` downscales *before* detecting, which is why none of it
  needs a background thread: the stored photo is 640pt wide, so working at
  twelve megapixels would be discarded effort. The camera is asked for on the
  tap, never at launch.
- **Card faces are drawn at the real ISO/IEC 7810 ID-1 ratio (1.586:1)**, with
  a material finish (matte/glossy/metal/frosted), a CSS/Shape-drawn EMV chip,
  and a contactless mark — all industry-standard components, not anyone's
  branding, so they're safe to draw. Do not draw issuer logos.
- **Three things make the drawn face read as an object rather than a coloured
  tile, and all three are easy to delete by accident.** A **bevel** — a
  hairline bright along the top edge and dark along the bottom, because light
  comes from above; without it a card is a rectangle printed on the page. **Two
  shadows** — a tight contact one *plus* a wide ambient one; a single soft
  shadow reads as a sticker. And a **surface pattern** (`CardPattern`,
  `CardPatternLayer`), one per palette colour, drawn at single-digit opacity.
  The moment a pattern is legible *as* a pattern it stops looking like a card
  and starts looking like wallpaper.
- **The patterns are CardWise's own and must stay abstract.** Hairlines, a fine
  grid, turned arcs, a soft bloom, vertical ribs. **Never draw one from an
  issuer's card** — a recoloured near-miss of a bank's pattern is worse than
  copying the file outright, because it is the same infringement plus a claim
  that it isn't. The pattern is derived from `artKey` rather than being its own
  user-picked field, so it costs no new `Card` property, no wallet migration
  and no extra decision — and it earns its place functionally, since two dark
  cards in the stack are then told apart by texture as well as hue.
- **`CardFinish` carries two numbers, not one, and `CardFinishTests` pins their
  order.** `sheenOpacity` is how bright the highlight is; **`sheenSpread` is how
  wide** — a gloss reflects the light source almost intact so its band is
  narrow, a matte surface scatters it wide and faint. Vary only the brightness
  and every card looks like the same plastic at a different exposure, which is
  what the app looked like before. Same reasoning as `BrandTint`: these live in
  CardKit as plain doubles precisely so a Linux test can catch someone
  inverting them, instead of a macOS runner and a human squinting at a PNG.
- **`CardThumbnail` is not a shrunken `CardFaceView` and must not become one.**
  It deliberately omits the surface pattern *and* uses no absolute type: the
  patterns are spaced for a card ~350pt wide, and at 62pt that spacing is four
  lines across the whole thumbnail — stripes, not texture. It keeps the
  material and the bevel, which are the parts that survive the size.
- **Copy is plain and second-person-adjacent**, never system jargon: "Switch
  it on" not "Activate", "You've used the whole $6,000 yearly bonus" not "cap
  exhausted". Keep new strings consistent with this register.
- **Avoid the AI-design tells the `frontend-design`/`artifact-design` skills
  flag**: no tracked-out ALL-CAPS labels, no monospace on labels (numbers
  only, for tabular alignment), no dot-joined meta strings.
- **Every number in `CardCatalog` cites the issuer's own page and the day
  somebody read it.** That is what `CatalogEntry` is for, and
  `CardCatalogTests` enforces it: an https URL on an issuer domain, never a
  review site, and one shared `checkedOn` date. Things the model cannot
  express go in `notModelled` as prose rather than being approximated into a
  rule — an approximation reads as a fact. Re-audit when `isStale` starts
  returning true (180 days).
- **Rotating quarters may never be invented.** This was violated once and the
  fake Q3/Q4 categories sat in the catalog for a whole build. `RotatingProgram`
  now has `knownThrough`, so "this quarter pays nothing extra" and "nobody has
  published this quarter" are different answers, and `status(for:)` returns
  `.unannounced` past the edge. Ship a quarter only with the issuer's own
  wording in `summary`; a test fails the build without it. Past the edge the
  app asks the user (`RotatingQuarterEditor`) — they got the email, and it is
  the only source that cannot go stale unnoticed.
- **The hand-typed form owns six fields; everything else rides along.** True
  of `CardEditorView.apply(to:)` when editing. The `template` half of this trap
  is gone with the quick-fill chips: a catalog card now arrives through
  `CardBenefitsView` whole, rotating programme and perks and caps included.
- **A card picked from the catalog carries its `productID`; a card typed over
  loses it.** `Card.catalogProductID` is what lets the app show a source and a
  date, offer "this is the wrong card", and one day match licensed artwork.
  `CardEditorView.apply(to:)` clears it deliberately — somebody who has retyped
  the rates is no longer making the catalog's claim about that product, and the
  card must stop being dated against the issuer's page.
- **`CardBenefit` is derived, never stored.** It is the card in plain English —
  "4x at restaurants" — read out of the rules, perks, rotating programme and
  signup bonus the ranking engine already uses. Storing a copy would be a
  second description of the same card, free to drift from the one that decides
  which card wins. Each benefit carries a `BenefitOrigin` saying which
  structure it came from, and `Card.removingBenefit(_:)` writes a user's
  correction straight back into that structure. **Do not build a second
  ranking path in the Benefits UI**, and do not add a parallel list of
  exceptions for the engine to learn about.
- **Two benefits refuse to be removed.** The base rate is what every other rule
  falls back to, and the rotating programme belongs to the issuer — hiding it
  would only hide it from the person it is being kept honest for.
- **The CardWise brand palette lives in `App/Theme/CardWiseColor.swift` and
  `App/Assets.xcassets`, and is deliberately separate from `CardArt`.**
  `CardArt` is the colours a user picks so their own card is recognisable —
  wide open on purpose, never brand colour. `CardWiseColor` is the app's own
  identity (`.cardWiseSuccess`/`.cardWiseWarning`/`.cardWiseError`, plus the
  `AccentColor` asset), applied only to chrome. The palette's neutrals
  (Charcoal, Slate Gray, Light Gray, Off White) are **not** wired in anywhere
  — `.primary`/`.secondary`/system backgrounds already mean those roles and
  adapt to Dark Mode; hardcoding the sheet's hex values for them would break
  contrast at night. `AppIcon` is a single 1024×1024 asset (Xcode 14's
  single-size format) — replace that one file, not a dozen sizes, if the icon
  ever changes.
- **A reminder is throttled at the moment it is scheduled (entry), not at the
  moment it is delivered.** `ReminderThrottle` (CardKit) enforces one per
  merchant per day and a daily ceiling; `RegionMonitor.didEnterRegion` checks
  and records against it before calling `notifier.schedule`. There is no code
  that runs at actual delivery to check against instead — see
  `ReminderThrottle`'s own doc comment for the one imprecision this accepts
  (an early exit still spends the day's count). `schedule(_:)` on
  `ArrivalNotifier` returns whether it actually scheduled something, so the
  throttle is only ever charged for a reminder that stood a chance of
  arriving.
- **`RegionMonitor.walletDidChange()` re-renders every still-dwelling
  arrival's notification, not just the region plan.** `ReminderCenter.schedule`
  writes content once, at entry, because nothing runs at delivery to write it
  again — deliberate, and documented on `ReminderCenter` itself. But editing a
  card requires the app to be open, so `walletDidChange()` calls
  `notifier.schedule(arrival)` again for everything in `tracker.pending`;
  `UNUserNotificationCenter.add` replaces a pending request under the same
  identifier rather than stacking one, so this is a correction, not a
  duplicate. Do not remove this call thinking the region-plan refresh alone
  covers it — it does not touch anything already past the geofence and into
  its four-minute wait.
- **Removing a card is Undo, not a confirmation dialog.** `WalletStore.remove(_:)`
  keeps the card and its original index in `lastRemoved` for six seconds,
  shown as a banner in `WalletStackView`'s `safeAreaInset` (has to survive the
  wallet going empty — removing your only card is exactly when you want it
  back). The photo file is **not** deleted at removal time any more —
  `sweepOrphanedPhotos()` does that once the window has genuinely closed, so
  Undo can restore the actual picture. If you ever need to delete a card's
  photo immediately and permanently, that is `eraseEverything()`'s job, not
  `remove(_:)`'s.

- **Rewards are never called "saved".** Nothing this app measures is a saving:
  no price changed and nothing was discounted. `BenefitEstimate` deliberately
  has no field, and the UI no string, containing the word — they are
  *estimated rewards*, at a rate the app believed applied and a point
  valuation the user set. And the figure worth reporting is
  `incrementalValueCents`: what choosing that card earned over the best other
  card in the same wallet. A 4x card earns 4x whether or not anything told you
  about it; being told is worth the gap, not the total. That number **may be
  negative** and is not clamped — when a signup bonus wins the ranking, the
  recommended card genuinely earns less at that till, and hiding it would make
  the total a sales figure rather than a measurement.
- **A cash back "unit" is one cent, not one dollar.** Rates and
  `WelcomeBonus.rewardUnits` are in the same units, and
  `RewardCurrency.centsPerUnit` values both: a 2% card has rate `2`, so a $200
  signup bonus is `20_000`. `CardBenefit` printed those units as dollars and
  read "$20,000 back" until this was found while writing the value engine.
- **The impact ledger holds a category, never a merchant.** No shop name, no
  id, no coordinate, anywhere in `ImpactEvent` — there is a test
  (`testNoEventCanCarryAMerchant`) that fails the build if one appears. The
  one structure holding a place identifier is `ImpactStore.openByRegion`, and
  only for the four minutes of a dwell, because entry and confirmation are two
  separate wakes of a process that is killed in between. `cardID` is the
  wallet's own row id and is stripped by `redactedForAnalytics()`, which is
  the *only* form an `AnalyticsService` is ever shown — enforced in one place,
  `ImpactStore.emit`, so a call site cannot forget.
- **`AnalyticsService` sends nothing and has no backend.** It ships as
  `NoOpAnalyticsService`. It exists so adding one later is a new conforming
  type rather than a change to every screen. Do not add a network call behind
  it without also adding the opt-in that Settings' copy currently promises is
  unnecessary.
- **Every `ImpactEventKind` has something that raises it.** An event model
  full of counters nothing emits is a dashboard where nobody can tell a broken
  metric from an unwired one. `cardRemoved` was written and then deleted for
  exactly this reason — a removal is undoable for six seconds, so the count
  would either be wrong or need a second correcting event. If you add a case,
  wire it in the same commit.
- **Staying quiet is counted, with its reason.** `RecommendationEngine.decide`
  returns `ArrivalDecision` — either the words *and* the frozen numbers, or a
  `SuppressionReason`. The old `reminder(for:cards:asOf:)` is still there as a
  thin wrapper for callers that only want the words. A product that counts
  only what it sent cannot tell restraint from a bug.
- **Saying "yes" to the follow-up does not close it.** An accepted suggestion
  keeps its entry in `ImpactLedger.open` with `answeredAt` set: the first
  question stops being asked, but the second and optional one — what did you
  spend — still needs the frozen numbers behind it. `expireStale` skips those
  when raising `.recommendationIgnored`, because somebody who said yes and
  never got round to a number has not ignored anything.

- **The design system is `App/Theme/CardWiseStyle.swift`, and nothing should
  hardcode a spacing or a radius.** `Metric` is an 8-point grid, `Metric.margin`
  is the one screen margin, and `.cardWisePanel()` is the surface everything
  sits on — with a *navy-tinted* shadow, because a grey shadow on a coloured
  ground is the single most common tell of an interface nobody looked at
  twice. `BenefitGroup.tint`/`.symbolName` make a category recognisable before
  its label is read, and the same green means groceries on every screen.
  The navy→blue gradient appears on exactly two surfaces (the Home header and
  the Impact hero); a gradient that turns up everywhere stops meaning
  anything.
- **A shelf colour has two values, lives in CardKit, and is tested.**
  `BenefitGroup.tintPalette` (`Packages/CardKit/Sources/CardKit/Theme/BrandTint.swift`)
  is a `BrandTint` — a light value and a dark one, as plain numbers.
  `BrandTintTests` fails the build if any of them stops clearing **3:1**
  against what it is actually drawn on, in either mode. It is in CardKit and
  not next to the SwiftUI precisely so it can be: a `Color` is opaque until a
  view renders it, three doubles are not.
  **Two roles, two accessors, and picking the wrong one is invisible until
  somebody photographs it.** `.tint` is for a glyph on a 14% wash of itself —
  it follows the interface style, because the background does. `.pinTint` is
  for a **solid** fill with a white symbol on it (a map pin, an `isOn` filter
  chip) — it is the darker value in *both* modes, because a pin is its own
  background and what has to survive is the white glyph. `MapCategory` has one
  of each: `.mapTint` for pins, `.listTint` for row icons.
  This exists because the Card perks icon shipped as Primary Navy on a
  near-black tile at **1.05:1** — present in the source, absent on the screen —
  and three map pins were under 3:1 in both modes at the same time. The line of
  code looked completely reasonable in every case.
- **Nothing in the shelf palette may be Error Red or Primary Navy**, and two
  tests enforce it. Error Red means errors and destructive actions; a shelf
  saying "your best rate here is 3%" in it is good news in the app's one colour
  for bad news. Primary Navy is the header gradient — the app's own frame,
  and lightening it enough to survive dark mode lands it ΔE 4.7 from Dining's
  blue, which is indistinguishable at icon size.
- **Home must not invent an opportunity.** `WalletInsights.opportunities`
  surfaces only things with a real action and a real deadline: a rotating
  quarter nobody switched on, and an open signup bonus. "Your $200 travel
  credit is unused" is the obvious third case and is deliberately absent —
  `Perk` records that a card *has* a travel credit, not its size, its reset
  date or whether it has been spent, and a guessed deadline in a list headed
  "worth doing" is the one somebody rearranges a week around. Same rule
  governs `expiringSoon`.
- **"Best for dining" has to be true of *this* wallet.**
  `WalletInsights.bestCategory` ranks the whole wallet and only labels a card
  with a category it actually wins. A 3x dining card sitting beside a 4x
  dining card gets no dining label — a small lie told on every scroll is still
  a lie, and this app's whole value is being right about which card to reach
  for.
- **CI photographs the app; that is the only way anybody sees it.** The
  `screenshots` job boots a simulator, installs a debug build, and relaunches
  it once per tab with `-CardWiseDemoSeed -CardWiseDemoTab <tab>`, light and
  dark, uploading PNGs as an artifact. Two of the names are not tabs:
  `impact` lands on More and pushes the impact screen, and `watching` lands on
  Map with the Watching chip already on — both because `simctl` cannot tap,
  and a screen two taps deep is otherwise unphotographable. One relaunch per screen rather than
  scripted taps: `simctl` cannot tap, and taps against a UI being redesigned
  are the flakiest part of any screenshot pipeline. `DemoSeed` is behind
  `#if DEBUG` *and* a launch argument, and writes to its own directory so it
  can never touch a real `wallet.json`. The job is `continue-on-error` — a
  flaky simulator boot must never block a correct change.
  **There is a third pass at the largest Dynamic Type size** (`huge-*.png`,
  four screens, light only), because every screen here is fixed-height tiles
  and `lineLimit(1)` — the exact combination that stops being a layout and
  becomes a row of ellipses. Text clipping does not change between
  appearances, so photographing it twice is not worth the runner time. The
  step puts `content-size` back to `medium` when it finishes, so anything
  added after it photographs the app at the size everybody else sees.
  `DemoSeed` also **registers** (never sets) a `preferredName`, so Home's
  greeting photographs as "Good morning, Oren" rather than the nameless
  fallback — the Settings field that sets it has existed since that screen was
  written; CI just never filled it in.
- **The repository is public, and CI depends on it.** Public repositories get
  GitHub Actions free; private ones get 2,000 minutes a month with macOS
  billed at **ten times** Linux, which is about 200 real macOS minutes. A
  single day of pushing exhausted that on 2026-09-13 and the repo went public
  the same day to fix it. If it is ever made private again, expect CI to die
  within a day — and expect the failure to lie to you: **every job fails
  instantly with zero steps run**, which reads as a broken build and is
  nothing of the kind. Check github.com/settings/billing before debugging any
  code. CardKit's tests deliberately run on Linux only; a second macOS copy of
  a Foundation-only suite is slower and tells you nothing new.
- **The map and the geofences ask two different questions, and must keep two
  different requests.** `MerchantSource`/`GooglePlacesSource` answers "which
  shops near here could earn something, so I can geofence one" — twenty at
  most, filtered to the wallet's earning categories, four fields, cached to
  disk for a week because it runs every few hundred metres whether anybody is
  looking or not. `PlaceSearchSource`/`GooglePlaceSearchSource` answers "what
  is around me" — including places nothing earns at, with a search box, a
  rating and, on tap, hours and a phone number; cached in memory for an hour
  because it only runs while somebody is holding the phone. **Do not fold
  them into one protocol.** One of those two sets of trade-offs would then be
  wrong, and the cost lands on the geofence path, which pays it unattended.
- **`MapCategory` and `SpendingCategory` are two axes, not two names for one
  thing.** `MapCategory` is what kind of shop it is (what a filter chip
  says); `SpendingCategory` is what a card pays there (what the engine
  ranks). A pharmacy is `MapCategory.other` and `SpendingCategory.drugstores`
  at the same time, and both are correct. `MapPlace.spendingCategory` is
  **optional** and nil is a real answer said out loud on screen — unlike
  `Merchant`, which refuses to exist without one, because a geofence that can
  never produce a recommendation wastes one of the twenty.
- **"Opportunity" on the map means a bonus rate, and is counted in one
  place.** `MapPlaceResult.isOpportunity` is true only when the winning
  card's rate is not its base rate. Home's "3 opportunities nearby" reads that
  count and no other, and shows an invitation rather than a number before the
  map has looked anywhere — the same rule as the rest of that screen.
- **The map does not re-query on a pan.** Each lookup is billed. Moving more
  than half the current radius from where the results were measured raises a
  "Search this area" button and waits. That half-the-reach rule is the same
  one `RegionPlanner.needsRefresh` uses, on purpose.
- **The list rows and the place detail draw a photograph of the actual shop,
  and the category tile is now the fallback.** This bullet used to say the
  opposite, and the reasoning it gave was half right: a shop front does tell
  somebody deciding which card to pull out nothing. But that is not the job.
  This screen is twenty rows of names, and what a photograph does is make one
  of them *the one you walked past this morning* — recognition, not
  categorisation. Oren asked for it on 2026-09-15 after the reverse had been
  argued twice.
  The costs the old note listed are real and are handled rather than denied:
  `PlacePhotoLoader` caches in memory, on disk for thirty days, and coalesces
  concurrent requests for the same image, so a photograph is paid for by the
  first person to look at it and nobody else. `PlacePhotoUse` is three size
  buckets, not a free-form number, so a row thumbnail is 264px and not a
  1170px hero scaled down twenty times. The attribution requirement is met on
  the place detail, where a credit can be read.
  **The fallback is not an apology and must not be treated as one.** Most
  places have no photograph, and the seeded CI run has none at all — so the
  category tile is what every screenshot shows and what most real rows show
  too. It is drawn as a designed tile (a gradient in the place's own colour,
  its glyph on top), not as a grey box waiting for something better.
- **CI cannot photograph a place photograph.** The screenshot job seeds
  `StaticPlaceSearchSource`, which has no photo handles and never calls
  Google, so `placecard` and `placedetail` show the fallback by construction.
  The photographic path is only visible on a build with a real Places key, on
  a device. Do not "fix" a screenshot that shows a category tile.
- **Adding a rating to the nearby-search field mask moved it from the
  Essentials SKU to Pro.** That is a real, deliberate bill — see
  `GooglePlaceSearchSource.searchFieldMask`. If it ever matters more than the
  stars do, drop `places.rating`/`places.userRatingCount` and the "Highest
  rated" sort with them. Hours, phone and website are *not* in that mask;
  they cost a details call, made for one place, only when somebody opens it.
  **`places.photos` was added to that mask and costs nothing extra**, because
  a field mask is billed by tier and the request is already at the tier the
  rating puts it in. What *is* separately billed is fetching the image bytes,
  once per photo per size bucket — which is why `PlacePhotoLoader` caches to
  disk for thirty days and coalesces in-flight requests. If photos ever need
  to be switched off, deleting `places.photos` from the mask does it: no
  handle means no fetch and every screen draws the fallback it already has.
- **An unrecognised `includedTypes` entry fails the whole Places request**
  with `INVALID_ARGUMENT` and returns nothing — not just its own results.
  `NearbyMapView` puts a lookup failure on the screen in words rather than
  showing an empty map, so a bad type is diagnosable on a device instead of
  reading as "nothing nearby" — **and that is exactly how this was found, on a
  phone, after CI had been green for days.** The Map read "The place lookup
  was refused (400). Unsupported types: grocery_or_supermarket" with zero pins.
- **Reading a place type and asking for one are two different vocabularies,
  and `PlaceTypeVocabulary` is the line between them.** A response can still
  carry `grocery_or_supermarket` or `lodging`, and dropping those would
  misfile a real shop — so the *reading* lists (`MapCategory.placeTypes`,
  `MerchantCategoryMap.placeTypes`) keep every legacy alias. A *request* must
  contain only what Places API (New) admits to knowing, so both request
  builders (`MapCategory.requestableTypes` /`placeTypes(for:)` and
  `MerchantCategoryMap.placeTypeNames(for:)`) filter through
  `PlaceTypeVocabulary.requestable`. The old comment demanded one list be both
  "deliberately conservative" and "covers both generations", which is not
  possible, and the second requirement quietly broke the first.
  **When unsure whether a type is still valid, put it in `legacyOnly`**: an
  invalid type costs the entire request, a valid one left out costs a few
  results a sibling type picks up anyway.
  **Both halves of the app had this bug, and only one of them showed it.** The
  Map says "could not look up nearby places". The geofence planner says
  nothing at all — a refused lookup there means no merchants, so no regions,
  so **no reminders ever**, which is indistinguishable from a quiet week.
  `PlaceRequestVocabularyTests` covers both.
- **CI cannot catch a Places bug.** The screenshot job seeds its own places
  (`DemoSeed.places`) and never calls Google, so the live API is only ever
  exercised on a real device with a real key. Green CI says nothing about
  whether a request is well-formed.
- **Every pin on the map is a `MapPinGroup`, even a group of one.** A high
  street puts twenty shops inside a hundred metres; drawn one pin each they
  heap up, the ones underneath cannot be tapped, and the heap does not even
  say how many are in it. `NearbyPlaces.pinGroups` is greedy, single-pass and
  deterministic — not the tightest clustering available, and deliberately so:
  a k-means that reshuffled between two identical refreshes would make the map
  twitch for no visible reason. Two details that are load-bearing: the group's
  **id is its lowest member's, not its first**, because an identity that
  changes under a re-sort makes SwiftUI rebuild every annotation; and the
  catchment is widened by `1/cos(latitude)` in longitude so it is a circle on
  the ground rather than an ellipse. The separation comes from the camera, not
  a constant — zoom in and shops come apart on their own.
- **The map's annotations are `Button`s, not `Map(selection:)`.** A tap on a
  cluster must zoom and a tap on a single shop must select it. One selection
  binding cannot say which happened, and working it back out of the tag was
  two code paths that had to agree with each other.
- **`RegionPlan.watchedPlaceIDs` is the join between the two halves of the
  app**, and it works only because both keep the place provider's own id
  (`Merchant.id` and `MapPlace.id`). It is what lets the map put a bell on the
  shops that already have a geofence — reminders arriving out of nowhere are
  the part of this app that feels like magic, and magic is what people
  distrust. **If a second place provider is ever added this join breaks
  silently, by matching nothing.** There is a test pinning it.
- **An empty state that names a filter carries the way out as a button.**
  The map's "nothing within 3 miles" offers "Widen to 5 miles" and "Show every
  kind of place". Telling somebody what to do and leaving them to go and find
  it is the kind of empty state that reads as an apology. The widen button is
  absent at ten miles, because a button that does nothing is worse than none.
- **The map's "Watching" chip reads `RegionPlan.watchedPlaces`, it does not
  filter the map's own results.** Those are two different sets: the geofence
  plan comes from `MerchantSource`, narrowed to the wallet's earning
  categories, from wherever the phone was when it was last redrawn; the map's
  results come from a different query with a different radius from wherever
  the map is looking now. A shop can be in one and not the other. Filtering
  would quietly show **fewer** than the twenty iOS is really watching — the
  exact wrong answer for somebody using this to work out why no reminder has
  arrived. Reading the plan gives the real twenty, costs no lookup at all, and
  cannot disagree with the thing it is reporting on. It also passes
  `ignoringDistance: true`, because a geofence four miles out is still one of
  the twenty. There is a test for each half of this.
- **`isShowingWatchedOnly` lives on the store, not in `MapFilter`, and is not
  persisted.** It is a diagnostic, not a taste. Somebody who left it on and
  opened the app three days later — after the plan was redrawn in another town
  — would meet an empty map and no clue why. It resets with the process.
  Turning it on also clears the category filter, so "watching" always means
  all of them rather than a set narrowed by a chip set ten minutes ago.
- **The Watching chip is shown even when nothing is watched, on purpose.**
  "CardWise is not watching anything yet, and here is what is missing" is
  precisely what somebody taps it for. Hiding the chip would hide the
  diagnosis along with the diagnostic.
- **Haptics: `.selection` on selecting a pin, `.impact(.light)` on opening a
  cluster, and nothing on dismissal.** Those are the two moments on the map
  that are a gesture rather than a tap on a button; closing a card is not an
  event, and a haptic on every dismissal is how an app starts feeling noisy.
  The cluster one fires on a counter (`clusterOpenings`) rather than the
  cluster's id, so zooming twice into the same cluster feels the same as
  zooming into two different ones. **This is the first haptic in the app** —
  the audit finding is still open everywhere else.
- **`RegionMonitor.StoredState` is internal rather than private so `DemoSeed`
  can write one.** That is its only other caller, and it exists so CI can
  photograph a map that is actually watching something. Do not build a
  `RegionPlan` anywhere else: a plan that did not come from `RegionPlanner` is
  a lie about what iOS has been asked to monitor. The seed builds its plan by
  running the real planner over its own places, so it can only ever contain
  states the app can really reach.
- **Haptics fire on a `Pulse`, and only at commit points.** `Pulse` (in
  `CardWiseStyle.swift`) is a counter, because `sensoryFeedback(_:trigger:)`
  watches a value for a *change* — triggering on the card that was removed
  means removing the same card twice fires once, and triggering on
  `cards.count` means an add and an undo feel identical. The full set, and why
  each is the pattern it is:

  | Moment | Feedback | Why |
  |---|---|---|
  | Pin picked up (wallet) | `.impact(.light)` | A thing leaving the stack |
  | Pin put down (wallet) | `.impact(.medium)` | It landed; heavier than the lift |
  | Undo a removal | `.success` | A recovery, which is what success means |
  | Select a map pin | `.selection` | A pick from several |
  | Open a map cluster | `.impact(.light)` | The map shifts under your thumb |
  | Prefer / unprefer a card | `.selection` | Small, reversible toggle |
  | Remove a card | `.impact(.medium)` | Significant, but undoable for six seconds |
  | Switch a quarter's bonus on | `.success` | The one action here that earns money |
  | Save a card | `.success` | Completes what somebody set out to do |
  | Erase everything | `.impact(.heavy)` | Asked for twice; a success chime for deleting your own data reads as the app being pleased about it |

  **What deliberately has none:** dismissing anything, switching a quarter's
  bonus *off* (that is somebody correcting a mistake, not earning), answering
  the follow-up, and every ordinary navigation tap. A haptic on every action is
  how an app starts feeling noisy, and the ones above only read as meaningful
  because most taps are silent.

  **Not gated on Reduce Motion**, because a haptic is not motion and iOS has
  its own switch for it (Sounds & Haptics › System Haptics) which
  `sensoryFeedback` already honours. Second-guessing that takes the choice away
  from somebody who has made it.

  **"Card saved" fires at the button, not in the wallet watching its count**,
  because `undoRemove()` also makes that count go up and the two must not feel
  the same.
- **`python scripts/brace-scan.py <files>` before pushing.** CI is the
  compiler, and a missing brace otherwise costs a full round trip to find. It
  understands comments, multiline strings, escapes and interpolation. OK does
  not mean it compiles; BAD means it definitely does not.

## Done vs. pending (build steps from the original spec)

| Step | Status |
|---|---|
| 1. Data model | Done |
| 2. Wallet UI (stack, add, edit, expand, pin, reorder) | Done. Onboarding redesigned around card *selection* (roadmap v2 steps 1-5). |
| 3. Recommendation engine, testable with no location | Done |
| 4. Region monitoring + notification pipeline | **Built and hardened, unverifiable without a device.** `RegionMonitor` registers the nearest 20 relevant merchants as `CLCircularRegion`s, handles enter/exit, applies a four-minute dwell, and redraws on significant location change. `ReminderCenter` schedules the local notification on entry and cancels it on exit; a tap opens that card. `ReminderThrottle` caps it at one reminder per shop and a daily ceiling, `RecommendationEngine.minimumArrivalEdgeCentsPerDollar` silences a trivial win, and `walletDidChange()` re-renders any notification still in its dwell window against a wallet edit. Nothing is registered in practice until step 5 gives `MerchantSource` somewhere to get shops from. |
| 5. Places API merchant resolution | **Done, needs a key.** `GooglePlacesSource` calls Places API (New) `searchNearby` behind `MerchantCache` (250m grid, one week, 40 squares, LRU). Resolution happens when the plan is redrawn, *not* when a geofence fires — the shop's name and category are already in the registered region by then. No key is committed; see `docs/places-api.md`. |
| 6. Significant-location-change travel mode | Not started |
| 9. Nearby Map (added, not in the original spec) | **Built, needs a key and a device.** A fifth tab: `NearbyMapView` over `NearbyPlacesStore`, drawing MapKit pins for whatever `PlaceSearchSource` returns, with filter chips, a distance, a search box, per-place card ranking and a detail screen. All the filtering/measuring/ranking is `NearbyPlaces.results` in CardKit and tested on Linux. With no Places key it shows location only and says so. Nothing about the map has been seen on a real phone — panning, selection and the "Search this area" threshold are exactly the parts CI screenshots cannot photograph. |
| 7. Safari extension | Not started |
| 8. Impact/value tracking | **Done, on-device only.** `RecommendationSnapshot` freezes the numbers at the moment a reminder goes out; `ImpactLedger` records generated/shown/opened/answered/priced and every *suppression* with its reason; `BenefitValueCalculator` turns a volunteered spend into an estimate and an incremental estimate. `ImpactStore` persists it to `impact.json`, `FollowUpPromptView` asks the one optional question on the wallet, `ImpactView` shows the total in Settings. `AnalyticsService` is the seam for a future backend and ships as a no-op. |

Also not built, flagged repeatedly, not yet done:

- Editing a cap's *limit* (only its spend is currently editable).

Two long-standing audit findings are now **done**, and the reasoning is worth
keeping:

- **Velocity on drag-to-reorder.** `WalletStackView.dragGesture` ends on
  `value.predictedEndTranslation`, not `value.translation`. Where the finger
  stopped is not where the card should go — a flick has momentum, and a stack
  that ignored it made a quick throw and a slow shove of the same length do the
  same thing, which is the single clearest way an iOS gesture can feel dead.
  Overshoot is free because `WalletStore.move(id:to:)` clamps, so the worst a
  hard flick can do is send a card to the top or the bottom, which is what a
  hard flick should do.
- **Haptics at commit points.** Nine of them, and the restraint is the design.

## Bugs already found and fixed (don't reintroduce)

- **`overflow: hidden` on a scroll container still scrolls.** The web
  preview's `.screen` needed `overflow: clip` — `hidden` let focusing a field
  inside a closed sheet scroll the whole phone and drag hidden UI into view.
- **Auto-focus without `preventScroll` drags the page around.** Every
  programmatic `.focus()` call in the web preview now uses
  `.focus({preventScroll:true})`.
- **Duplicate SVG gradient `id`s across repeated elements silently break.**
  The card chip was originally SVG with a shared gradient id; every card past
  the first rendered it black. Redrawn in CSS (web) / SwiftUI `Canvas`/`Shape`
  (Swift) — no ids to collide.
- **A test server without an explicit charset mangles curly quotes.** Python's
  `http.server` needs `guess_type` overridden to force `text/html;
  charset=utf-8`, or `""` renders as mojibake — this was a test-harness bug,
  not a real one, but cost real debugging time before that was clear.
- **`NumberFormatter` currency formatting differs between Darwin and Linux.**
  `maximumFractionDigits = 0` is honoured on macOS and ignored on Linux, so
  `RecommendationEngine.dollars(325)` is "$325" on the macOS job and "$325.00"
  on the Linux one. CardKit is tested on both, so **never assert an exact
  currency string** — assert that it contains the digits. iOS is the only
  platform the app ships on, so the formatting itself is not a bug; a test
  that cares which CI job ran it is.
- **`.background` is pure black in dark mode, and so is the page under it.**
  `.cardWisePanel()` filled with `.background` (= `systemBackground`) while
  every screen sits on `systemGroupedBackground`. In light mode that is white
  on grey and looks right; at night both are `#000` and every panel in the app
  was black on black, separated only by a navy shadow that is itself invisible
  against black. The map's dense list showed it as a column of floating text
  with no cards under it. The fix is the role that means what was meant:
  `secondarySystemGroupedBackground` for a card on a grouped page,
  `tertiarySystemGroupedBackground` for a tile on a card. **The same trap in
  miniature caught the map's search field and filter chips**, which used
  `.background.secondary` — visible at night, invisible on the light grouped
  background. If a surface disappears in exactly one appearance, this is why.
- **A hierarchical style on a material paints nothing.** The map's bottom
  sheet was `.background(.regularMaterial)`, and every `.foregroundStyle(
  .secondary)` inside it — the facts line under each place name, the
  "CardWise recommendation" label, the runner-up sentence — plus every
  `Divider()` rendered as **completely blank**. Not faint: measured at exactly
  the background's own luminance across all 77 points where they should have
  been, in light *and* dark. A material applies vibrancy to hierarchical
  styles, and over a broad uniform blur `.secondary` resolves to the material
  itself. `.primary` and explicit `Color`s were unaffected, which is what made
  it read as a spacing bug rather than a painting one — the layout was
  correct, the space was reserved, nothing was drawn in it.
  **Two rules came out of it.** A large content surface uses
  `secondarySystemGroupedBackground`, not a material — materials are for small
  floating controls (the search field, the chips), where they work and look
  right. And **anything drawn over a material or a photograph uses an explicit
  `Color`**: `Color.secondary`, not `.secondary`; `Hairline`, not `Divider`.
  This is the third variant of the same family of bug in this file, after
  `.background` in dark mode and `.background.secondary` in light. **If
  something is laid out but invisible, look at what it is drawn *on* first.**
- **`Color` and `HierarchicalShapeStyle` don't unify in a ternary** passed to
  `.foregroundStyle(...)` — write `condition ? Color.x : Color.y` explicitly.
  **This one was hit a second time, by Claude, in the same file, after this
  exact warning was already written down.** `cap.isExhausted ? .cardWiseWarning
  : .secondary` failed to build because `.secondary` resolved against
  `ShapeStyle` and `cardWiseWarning` is only declared on `Color`. CI caught it;
  it would not have been caught by reading the diff. Read this bullet before
  writing a color ternary in a SwiftUI modifier, not after CI fails on it.

## Working with this repo as Claude

- Windows dev machine (git-bash `Bash` tool + PowerShell both available; CRLF
  warnings on `git add` are expected and harmless).
- **The Bash tool's heredocs eat backslashes, even quoted ones.** Writing Swift
  through `cat > file <<'EOF'` silently mangles `\(interpolation)` and every
  escape in a string literal, and a long one can break the heredoc outright.
  Write Swift with the `Write` tool, or with a Python script written by `Write`
  and then run. Small `sed`/`python -c` edits with no backslashes are fine.
- CI is the compiler, so before pushing it is worth a crude structural check
  (brace/paren balance across the changed files) — it catches the mistakes that
  waste a whole CI round trip.
- Push small, watch `gh run watch <id> --exit-status`, report the actual CI
  result — see the opening section.
- There is no local preview. See "There is no web preview any more" above:
  nothing is visually verifiable before CI, and that is the trade.
