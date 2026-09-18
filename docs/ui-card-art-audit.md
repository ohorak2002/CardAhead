# UI and card-art audit

Date: 2026-09-18. Scope: Home recommendation, Wallet, shared card faces and
thumbnails, expanded card details, supporting theme, CardKit art resolution,
tests, and CI. This is a source audit on Windows, not a rendered UI review.

## Evidence and ranked findings

| Rank | Finding and source evidence | Direction |
|---|---|---|
| P1 | `HomeView.header` places a large greeting, slogan and opportunity banner before `bestCardNow`. `RecommendationHero` names the winner mainly inside a reward sentence below the art. | Compact the header; lead the panel with “Use this card” and the full winner name. Keep place context adjacent and comparison secondary. Two-second recognition remains a device acceptance test. |
| P1 | `CardFaceView.licensedArt` and `CardThumbnail.licensedArt` construct `Image(name)`, which does not establish that the asset exists. Both use fill/crop; the face adds text, chip and sheen without consulting modification permission. | Load bundled art with a failable UIKit lookup. Render licensed images fitted and unmodified, with no clipped corners or synthetic overlay. Missing licensed pixels resolve to the procedural face. Test that display-source decision in CardKit. |
| P1 | `WalletStackView` attaches `DragGesture` to every face and estimates slots from `summaryHeight = 40`, although `RewardSummary` wraps to variable height. It uses `onTapGesture` without an expansion value. | Native Button for expansion, a visible state label, full card proportions, and a separate native reorder list. Native drag handles plus move-up/down alternatives remove the approximate slot calculation and scroll conflict. |
| P1 | `RewardSummary.FlowRow` measures every child with `.unspecified`, then places an oversized child at that width. Long labels can escape the available width at large text sizes. | Constrain both measurement and placement to the row width; preserve multiline height. |
| P2 | `CardFaceView` has fixed tiny typography, a chip at the bottom edge, full-face diagonal sheen, and a strong uniform shadow. The hero narrows the face to 210pt without adapting its type. | Draw a proportionally scaled, original face with vertically grouped identity, mid-left chip, restrained finish-specific texture, edge lighting, and the existing optional preferred name. Keep full semantic text outside the artwork at accessibility sizes. |
| P2 | `RecommendationHero` marks a combined container as a button although only its child button has an action. `HeaderButton` is 36pt. Wallet undo truncates the removed name. | Keep the real map button separate, use at least 44pt targets, wrap undo text and use a solid semantic surface. |
| P2 | `CardWiseSecondaryButtonStyle` uses fixed dark blue on dark panels; `CardDetailView` uses pale card-art accents for controls. Reduce Motion disables spring timing but not Wallet's drag scale/tilt. | Add a semantic action-ink color without altering brand gradients, separate art from controls, adapt detail rows at accessibility sizes, and remove custom drag transforms. |
| P3 | `.github/workflows/ci.yml` already captures light/dark and largest text, but not reorder. README/CLAUDE retain historical claims about macOS tests; the actual test job is Linux only. | Extend existing screenshot coverage without adding a runner; report the actual workflow jobs. |

## Design direction

The recommendation is the first substantial content on Home: action, winner,
nearby place, recognisable face, reward and supporting reason. Keep existing
ranking and nearest-opportunity selection. Do not imply physical arrival from
a nearby result. Keep the wallet's chosen order independent of ranking.

Wallet uses whole 1.586:1 faces, quieter shadows and clear spacing. Expansion
joins a card to its details with a visible disclosure state. Full faces are a
deliberate safer equivalent to restoring an overlapping fan: the existing
Wallet comments document prior width collapse and hidden identities in that
layout. A compact native reorder sheet exposes the whole order and provides
system scrolling and drag behavior instead of estimating variable row heights.

Procedural art remains original: plain issuer/product words, user-selected
palette and finish, generic contact geometry, static fine texture, a small
optional preferred name. No fake card number, expiry, issuer emblem, network
logo, or issuer-specific pattern. No image downloads or generated replicas.

## Card-art safety assessment

The shipping registry is empty and `testLibraryShipsEmpty` protects that fact.
Approval, product identity, allowed use and dates are already checked in
`CardArtLibrary`. Preserve those gates and the licensed → user photo → drawn
selection. File availability is a separate rendering concern, currently missing
for licensed images; a failed load must also change the spoken source.

Use fitted, unmodified licensed art even when a grant permits more. This avoids
interpreting crop/overlay permission in each view. The photo pathway stays
on-device through `CardPhotoProcessor` and `WalletStore`; no OCR, upload,
telemetry, or new persistence fields are part of this work. Unsaved photo
previews must still display, and deleted photos must still draw a fallback.

This is an engineering assessment of the repository's permission boundary,
not a legal clearance. Existing documentation's broad claims about photos or
contactless marks are not proof of redistribution rights. Future licensed
assets still require review of territory, attribution placement, screenshot
rights and the actual written grant before the empty registry changes.

## Verification matrix

| Surface / behavior | Local structural evidence | Apple/device acceptance required |
|---|---|---|
| CardKit display source | Targeted XCTest cases for missing licensed image, missing photo, unsaved preview and licensed priority | `CardKit on Linux` must pass all tests |
| SwiftUI compatibility | Brace scan, diff check, manual API/call-site review | `iOS app builds` simulator build |
| Home hierarchy | Winner text precedes artwork; no header status banner before recommendation | Light/dark Home screenshots; identify card and place within two seconds on a real phone |
| Wallet and reorder | No custom slot estimation; native list move uses existing store methods | Drag first/middle/last rows, cancel a drag, move actions, relaunch persistence, expand/collapse, notification deep link |
| Card artwork | Empty registry, no new image assets, shared material and loader | All ten palettes × four finishes, 210/260/full widths, long names, saved/unsaved/deleted photo; test-only licensed fixture with missing file and mismatched aspect ratio |
| Accessibility | Semantic buttons, disclosure value, constrained flow layout, adaptive detail actions | Largest text, VoiceOver reading and activation order, Switch Control, 44pt targets, Increase Contrast, Reduce Motion, Reduce Transparency |
| Privacy and persistence | No changes to photo processor, photo storage or card serialization | Photo choose/retake/remove, add/edit, remove/undo and cold launch |
| CI screenshots | Existing workflow inspected; add reorder coverage | Inspect `CardWise-screenshots` files, including `huge-*`; job is allowed to fail and is not a visual assertion |

## Verification results

Implemented the recommendation-first hierarchy, native reorder sheet, explicit
expansion buttons/state, full card identities outside artwork, adaptive detail
actions and status rows, constrained wrapping, semantic action ink and 44pt
header/undo/move targets. Removed the decorative hero entrance and custom
reorder scale/tilt. Expansion respects Reduce Motion; undo uses opacity and a
solid grouped surface. The empty recommendation panel opens the nearby map.

The full face and thumbnail now share materials and a failable bundled-image
loader. User photos no longer acquire synthetic chips or type over their own
printing. Licensed faces are fitted without clipping or overlays. The optional
existing preferred name is used only on procedural art. CardKit adds a pure
display-availability reconciliation method and six regression tests. No asset,
photo-storage, card-schema or ranking-engine changes were made.

Local results:

- `python scripts/brace-scan.py <all App and Packages Swift files>`: **131 OK**.
  The scanner does not type-check Swift. Its output was also checked for BAD
  rows because the script itself does not return a failing exit code for them.
- `git -c core.safecrlf=false diff --check`: **pass**.
- PyYAML parsing of `project.yml` and `.github/workflows/ci.yml`: **pass**;
  expected four jobs and reorder in all three screenshot passes: **pass**.
- JSON parsing of all eight asset-catalog JSON files: **pass**.
- Empty licensed registry, unchanged asset files and Foundation-only CardKit
  import boundary: **pass**. Photo processor/store, Card model and recommendation
  engine are unchanged.
- Conservative sRGB math over both stops of all ten palettes and all four
  finishes: white ink minimum **4.73:1**, combining maximum lighting layers
  even though their maxima do not coincide. Action ink minimum **7.16:1** over
  sampled light/dark panel and button grounds. These are numerical bounds, not
  rendered contrast or visual proof.
- The first Python audit harness stopped on Windows' default text encoding;
  rerunning with explicit UTF-8 passed. No product code failure was inferred.
- Six added `CardArtLibraryTests` cover missing licensed pixels, loaded licensed
  priority, deleted photos, unsaved photo previews, refused grants and a
  wallet-only grant requested for app display. **Not executed locally**.

No Swift compiler, XcodeGen or xcodebuild is available on this Windows machine.
No Swift compilation, XCTest pass, visual correctness or two-second recognition
is claimed. No commit, push, workflow dispatch or pull request was performed.

## Exact remaining GitHub Actions checks

After these local changes are separately committed and made available on a
remote branch, run **Actions → CI → Run workflow → that branch** (or
`gh workflow run ci.yml --ref <that-branch>`). A run against the current remote
revision cannot validate these uncommitted files. Record the run's commit SHA.

1. **CardKit on Linux** (`linux`): `swift test --package-path Packages/CardKit`
   must pass the whole suite, including the six new art tests, existing licence,
   catalog/model, ranking and runner-up tests.
2. **iOS app builds** (`app`): XcodeGen generation and `xcodebuild build -project
   CardWise.xcodeproj -scheme CardWise -destination 'generic/platform=iOS
   Simulator' CODE_SIGNING_ALLOWED=NO` must succeed.
3. **Screenshots** (`screenshots`): inspect `CardWise-screenshots`, especially
   `1-home.png`, `3-wallet.png`, `13-carddetail.png`, `17-reorder.png`, their
   `dark-*.png` and `huge-*.png` equivalents, and the cardphoto/cardpreview/
   cardbenefits screens sharing the face renderer. This job is non-blocking;
   a green overall run is not evidence that its images exist or look correct.
4. **Installable app for sideloading** (`ipa`): workflow dispatch must produce
   `CardWise-unsigned-ipa` for the same SHA. Archive uses generic iOS with code
   signing disabled. Install via the existing iPhone runbook.

## Exact remaining real-iPhone checks

1. On a small phone and a current larger phone, open Home with real nearby
   results. Identify the winning card and the named place in two seconds at
   default text size. Check long issuer, product and place names; no results,
   unknown categories, one card, flat-rate wallets and empty wallet must remain
   honest. Opening the hero goes to the nearby map, not directly to a place.
2. Wallet: expand/collapse first, middle and last cards; scroll over faces
   without reordering; open Reorder, drag through a long list, cancel a drag,
   move one slot via arrows, verify boundaries, close and relaunch to confirm
   saved order. Remove and undo, including the only card. A notification tap
   must still expand and scroll to the named card.
3. Repeat Home, Wallet, details and Reorder in light/dark, largest accessibility
   text, Bold Text and Increase Contrast. Inspect all ten art palettes and four
   finishes at compact/full widths; inspect tiny chip traces, long names and
   optional preferred name. Watch scrolling for texture-rendering cost.
4. VoiceOver: winner/place/reward reading order, separate map action, source
   description, collapsed/expanded value, all detail controls, move actions and
   changed positions. Use Switch Control and confirm all touched actions are
   reachable without dragging. Inspect targets with Accessibility Inspector.
5. Enable Reduce Motion and Reduce Transparency: no hero entrance, tilt or
   scale; expansion and undo remain understandable; native reorder behavior
   follows the system setting. Undo text and action must remain legible.
6. Choose/take a photo, preview before saving, save, relaunch, remove and retake.
   Missing/deleted photo draws a procedural face with matching spoken source.
   Use an original test-only licensed fixture in a non-shipping build to check
   missing bundle pixels, denied crop/modification, non-card image aspect ratio,
   and appDisplay vs walletDisplay. Never add an unlicensed issuer front to
   obtain this evidence; the shipping registry stays empty.

## File inventory

- `.github/workflows/ci.yml`
- `App/Theme/CardArtwork.swift` (new)
- `App/Theme/CardWiseControls.swift`
- `App/Theme/CardWiseStyle.swift`
- `App/Views/CardDetailView.swift`
- `App/Views/CardFaceView.swift`
- `App/Views/CardThumbnail.swift`
- `App/Views/HomeView.swift`
- `App/Views/RecommendationHero.swift`
- `App/Views/RewardSummary.swift`
- `App/Views/RootTabView.swift`
- `App/Views/WalletStackView.swift`
- `Packages/CardKit/Sources/CardKit/Data/CardArtLibrary.swift`
- `Packages/CardKit/Tests/CardKitTests/CardArtLibraryTests.swift`
- `docs/ui-card-art-audit.md` (new)

## Deliberately deferred

- Overlapping fan layout and custom inertial reordering: full identities and native reorder are safer with variable text heights.
- New per-card nickname storage and richer personalization editor: existing name, palette, finish and optional preferred name suffice for this pass.
- Broader Map, Benefits and tab-shell redesign; live place-photo/API testing.
- Licensed-asset onboarding, territory enforcement and redistribution review before any real asset is admitted.
