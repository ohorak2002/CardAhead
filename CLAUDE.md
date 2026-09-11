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
                         Perk, CardFinish
    Engine/             PurchaseContext, CardScore, RecommendationEngine
    Data/               CardCatalog (seed cards), MerchantCategoryMap,
                         CardArtLibrary (licensed card art registry)
    Geo/                GeoCoordinate, Merchant, RegionPlanner (which 20
                         places to watch), ArrivalTracker (the dwell rule),
                         MerchantSource
    Engine/ArrivalReminder.swift   the words on the lock screen, decided by
                         the ranking engine so they can be unit tested
    Places/             GooglePlacesSource, MerchantCache, and an HTTPRequest
                         value type so no URLSession enters this package
  Tests/CardKitTests/    run on both macOS and Linux CI
App/
  Models/ (none — CardKit owns them)
  Store/WalletStore.swift        wallet CRUD, photo storage, JSON persistence
  Location/LocationAuthorization.swift   the permission ladder
  Location/RegionMonitor.swift           CLCircularRegion plumbing only
  Location/ArrivalNotifier.swift         seam between arriving and being told
  Notifications/ReminderCenter.swift     UNUserNotificationCenter, both ends
  Places/PlacesProvider.swift            URLSession, and the API key or not
  Views/                         see below
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

## The app's three screens

1. **Wallet** (`WalletStackView`) — home, and *only* the cards plus a way to
   add one. A phone screen holding two subjects at once is a phone screen
   nobody reads — this was a deliberate redesign partway through the session;
   don't add non-card content back onto it. A "Why this card" bar at the
   bottom pushes to screen 2.
2. **Why this card** (`WhyThisCardView`) — the ranking, the reasoning, the
   caveats, and a hand-driven "where you are" control standing in for the
   geofence until step 4 lands.
3. **Settings** (`SettingsView`) — behind a gear, top-left of the wallet
   toolbar. Point valuation (per currency, not per card), location status,
   card-artwork explainer, erase-everything.

Adding/editing a card is `CardEditorView`, a sheet, not a fourth screen.

## Conventions established this session

- **A fresh wallet starts empty. Never preload cards.** `CardCatalog` is a
  typing shortcut *inside* the add flow (quick-fill chips), never a seeded
  starter wallet. `WalletStore`'s doc comment states this explicitly — read it
  before touching `init`/`load`.
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
- **Issuer card art is never shipped without a recorded licence.**
  `CardArtLibrary.assets` ships empty on purpose, with a test
  (`testLibraryShipsEmpty`) asserting it stays empty until someone deliberately
  adds an entry per `docs/card-art.md`. `CardArtSource.resolve(for:)` is the
  only way to pick a face: licensed asset → user's own photo → drawn card.
  Never bypass this to hardcode an issuer's logo/art.
- **Card faces are drawn at the real ISO/IEC 7810 ID-1 ratio (1.586:1)**, with
  a material finish (matte/glossy/metal/frosted), a CSS/Shape-drawn EMV chip,
  and a contactless mark — all industry-standard components, not anyone's
  branding, so they're safe to draw. Do not draw issuer logos.
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
- **The add-card form owns six fields; everything else rides along.** This is
  true of `CardEditorView.apply(to:)` when editing *and* of `template` when
  adding from a quick-fill chip. Break the latter and a catalog card arrives
  in the wallet with no rotating programme, no perks and no caps.

## Done vs. pending (build steps from the original spec)

| Step | Status |
|---|---|
| 1. Data model | Done |
| 2. Wallet UI (stack, add, edit, expand, pin, reorder) | Done |
| 3. Recommendation engine, testable with no location | Done |
| 4. Region monitoring + notification pipeline | **Built, unverifiable without a device.** `RegionMonitor` registers the nearest 20 relevant merchants as `CLCircularRegion`s, handles enter/exit, applies a four-minute dwell, and redraws on significant location change. `ReminderCenter` schedules the local notification on entry and cancels it on exit; a tap opens that card. Nothing is registered in practice until step 5 gives `MerchantSource` somewhere to get shops from. |
| 5. Places API merchant resolution | **Done, needs a key.** `GooglePlacesSource` calls Places API (New) `searchNearby` behind `MerchantCache` (250m grid, one week, 40 squares, LRU). Resolution happens when the plan is redrawn, *not* when a geofence fires — the shop's name and category are already in the registered region by then. No key is committed; see `docs/places-api.md`. |
| 6. Significant-location-change travel mode | Not started |
| 7. Safari extension | Not started |

Also not built, flagged repeatedly, not yet done:

- **Undo on Remove** (or a confirmation on it) — the one item from the Apple
  fluid-interfaces audit still outstanding.
- **Velocity/momentum on the drag-to-reorder gesture** —
  `value.translation` should become `value.predictedEndTranslation`, a
  near-one-line fix. This was the #1 finding in the audit.
- Haptics (`sensoryFeedback`) at commit points — audit finding, not started.
- Editing a cap's *limit* (only its spend is currently editable).

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
- **`Color` and `HierarchicalShapeStyle` don't unify in a ternary** passed to
  `.foregroundStyle(...)` — write `condition ? Color.x : Color.y` explicitly.

## Working with this repo as Claude

- Windows dev machine (git-bash `Bash` tool + PowerShell both available; CRLF
  warnings on `git add` are expected and harmless).
- Push small, watch `gh run watch <id> --exit-status`, report the actual CI
  result — see the opening section.
- Local preview server for the web mirror: `.claude/preview-server.py` +
  `.claude/launch.json` (`preview_start` with name `card-preview`, port 8099).
  Use forward slashes in any path passed to the launcher — backslashes get
  mangled by the launch-config parser.
- When editing the web preview's `<script>` block, syntax-check before
  publishing: extract it and run `node --check`.
