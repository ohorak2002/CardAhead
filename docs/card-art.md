# Card artwork

The app never sees a card number, so the card's face is how a user tells their
cards apart. Getting that face right matters more here than it would in most
apps. This is how to do it without getting the app pulled.

The rule it all comes down to:

> **Exact when licensed. Personal when photographed. Beautiful when drawn.**

Nothing here is legal advice, and no implementation is "legally safe" by
construction. What the architecture does is make the licensing position
*explicit and auditable*, and make the failure direction always the same one:
when anything is unclear, missing or broken, the app draws its own card.

## Why we cannot just use the real art

Apple Wallet shows the genuine Amex Platinum front because **American Express
sends Apple that image** when the card is provisioned. The artwork travels with
the tokenisation handshake between the issuer, the payment network and Apple.
It is a business relationship, not a public asset.

Issuer card faces and logos are trademarked, and usually copyrighted as well.
Copying them into a third-party app is infringement even if the app is free,
even if it is flattering to the bank, and even if the file was easy to find.
Apple's App Review rejects for this, and issuers do send takedowns.

So the app draws its own card faces, and offers two legitimate routes to a
real one.

## The three sources, in priority order

`CardArtSource.resolve(for:use:asOf:)` picks the first that applies, and it is
the **only** way any view chooses a face. Nothing draws a card without going
through it.

| Source | When it applies | Whose it is |
|---|---|---|
| `.licensed` | A recorded, approved, current grant covers this product *for this use* | The issuer's, used with permission |
| `.userPhoto` | The user photographed their own card | Theirs, always fine |
| `.drawn` | Everything else — the default, and today the only one | Ours |

Never reverse that order, and never add a fourth thing below `.drawn`: the
drawn face is always available, which is what makes every failure above it
survivable.

The drawn face is not a placeholder to be embarrassed about. It uses the real
ISO/IEC 7810 ID-1 proportion (1.586:1), a material finish, an EMV chip and the
contactless mark — which is most of what makes a card look like a card. Those
are industry-standard components, not anyone's branding.

**What the drawn face must never do is imitate a particular issuer's design.**
Not a recoloured copy, not the same composition with the logo removed, not a
"close enough" version of a proprietary pattern. `CardArt` in
`App/Theme/CardArt.swift` is a palette of plain colour words — Midnight, Gold,
Steel — and that is deliberate. The user picks the one nearest their card so
they can recognise it in the stack. It is not an attempt to reproduce the card.

## The four things a licence has to answer

The model is in `Packages/CardKit/Sources/CardKit/Data/CardArtLibrary.swift`,
and it keeps four questions apart on purpose, because collapsing any two of
them is how an app ends up showing artwork it is not entitled to.

1. **Where did the file come from?** `ArtLicence` — issuer-provided, an
   affiliate programme, or the user's own camera.
2. **What state is the grant in?** `ArtLicenceStatus` — `pendingReview`,
   `approved`, `revoked`. Note there is no `expired`: that is arithmetic on
   `expiresOn`, not a state somebody has to remember to update.
3. **What does it cover?** `ArtUse` — `walletDisplay`, `appDisplay`,
   `marketing`, `appStore`. **In-app rights are not marketing rights.**
   Permission to draw a card inside the app is not permission to put it in an
   App Store screenshot, a website hero or a pitch deck, and brand kits
   routinely grant the first and withhold the rest.
4. **When?** `effectiveDate` and `expiresOn`.

`CardArtAsset.isUsable(for:asOf:)` is the single gate all four run through.
Everything else — the views, the thumbnail, the attributions list — asks it
rather than forming its own opinion.

Provenance is not permission. An asset the issuer definitely emailed us is
still refused while its status says pending. There is a test for exactly that.

## Everything fails towards the drawn card

This is the part worth keeping if nothing else survives a rewrite.

| What goes wrong | What happens |
|---|---|
| Grant still pending | Drawn card |
| Grant revoked | Drawn card |
| Grant lapsed | Drawn card |
| Grant has not started yet | Drawn card |
| Grant covers marketing only | Drawn card |
| `license.json` missing its status | Reads as `pendingReview` → drawn card |
| `license.json` missing its uses | Reads as none → drawn card |
| `license.json` malformed | Refused, not thrown → drawn card |
| Image file missing from the bundle | Drawn card |
| User photo file deleted | Drawn card |
| Card typed in by hand, no product id | Drawn card |

`CardArtLibraryTests` asserts every row of that table. If you change this
system, keep them passing — and if you have to choose, choose the direction
where a bug loses a licensed image rather than one where a bug shows an
unlicensed one.

## Keyed on the product id, never on the name

`CardArtLibrary.asset(for:)` matches `Card.catalogProductID` against
`CardArtAsset.productID`. It does **not** match on issuer and card name, and it
used to, which was wrong twice over:

- A card somebody typed in by hand as "Amex" / "Gold" would pick up artwork
  granted for the catalog product, which is not evidence they hold it.
- An issuer renaming a card would silently lose its artwork, which is the exact
  thing `CatalogEntry.productID` exists to prevent.

A card with no product id therefore never matches a grant. That is the safe
answer, and it is tested.

## Versioning

`CardArtAsset.assetVersion` is the printing of the card — `2026-01`. Issuers
redesign, and when they do, the new face is a **new asset beside the old one**,
not an overwrite of a file some grant was written against. The newest usable
version wins; a redesign whose grant has not come through yet falls back to the
older licensed one rather than dragging it down.

## Adding a licensed asset

`CardArtLibrary.assets` ships empty, and there is a test asserting that it stays
empty. **That test failing is the point** — it forces a deliberate decision
rather than a quiet commit.

Before adding an entry, all of these must be true:

1. **You have the grant in writing.** An email from the issuer's brand or
   partnerships team, or acceptance into a card-marketing programme whose
   terms explicitly cover displaying card imagery in an app.
2. **The grant covers this use.** Many brand kits permit editorial or
   comparison use but not "display as the user's own card in a wallet
   interface". Read the clause, not the headline, and tick only the `ArtUse`
   values it actually names.
3. **You can produce it on request.** Store the email or terms PDF somewhere
   the whole team can find, and put its identifier in the licence's reference.
4. **You have both dates.** `effectiveDate` and `expiresOn`. Grants get
   withdrawn and programmes change; an asset past its end date stops drawing on
   its own.

Then, in order:

1. Put the image and its `license.json` under `CardArt/Licensed/<issuer>/<productID>/<version>/`.
   The schema is in [`CardArt/Licensed/README.md`](../CardArt/Licensed/README.md).
2. Add the image to `App/Assets.xcassets` under the manifest's `imageName`.
3. Add the entry to `CardArtLibrary.assets`:

```swift
public static let assets: [CardArtAsset] = [
    CardArtAsset(
        id: "example-everyday-2026-01",
        productID: "example-everyday",     // must match a CatalogEntry.productID
        issuer: "Example Bank",
        cardName: "Everyday",
        assetVersion: "2026-01",
        imageName: "example-everyday",     // asset catalog entry
        licence: .affiliateProgramme(
            name: "Example Partners",
            termsURL: "https://example.com/partner-terms"
        ),
        status: .approved,
        permittedUses: [.walletDisplay, .appDisplay],
        effectiveDate: ...,
        expiresOn: ...,
        croppingAllowed: true
    )
]
```

4. Change `testLibraryShipsEmpty` to assert the expected count, and add a test
   pinning what this grant does and does not cover.
5. Say in the commit message which grant the entry rests on.
6. Check the debug audit (Settings → Card artwork, DEBUG builds) on a device:
   it lists every card's resolved source and every registry entry's status.

If a grant is withdrawn, set `status` to `.revoked` rather than deleting the
entry. The history is worth keeping, and deletion invites somebody re-adding it
next quarter.

## Where to actually get grants

Realistic routes, roughly easiest first:

- **Card affiliate networks.** Issuers who pay for card signups often supply
  approved card images to publishers. The terms usually cover display. This is
  the most likely route for an app like this one, and it comes with a revenue
  model attached.
- **Issuer brand and partnership teams.** Slower, but a direct grant is the
  cleanest thing to hold.
- **Card network marketing programmes.** Visa and Mastercard run partner
  programmes; these cover the network marks, not the issuer's own face.

One issuer relationship can unlock several products at once, which is why the
architecture is built so adding an issuer is data plus a manifest plus a test,
and not a change anywhere else.

Do not assume an affiliate relationship grants artwork rights on its own, and
do not assume permission to use a logo extends to the whole card design.

## Payment network marks

Visa, Mastercard, American Express and Discover marks are trademarks in their
own right, separate from the issuer's card design, and are not free to use
commercially just because they are recognisable. The app currently draws none
of them, and `CardNetwork` is used as a *word* in the product list — "Visa, no
annual fee" — rather than as a logo. Keep it that way unless a network
programme specifically covers the use.

## The user's own photo

The middle tier, and the only route to an exact card face today.

- `CardPhotoView` is the screen, reachable from the card itself in
  `CardBenefitsView` rather than buried in the hand-typed form. Somebody who
  picked their card from the catalog is exactly the person who wants it to look
  like the one in their pocket.
- `CardPhotoProcessor` finds the card's four corners (`VNDetectRectanglesRequest`),
  flattens the perspective onto them (`CIFilter.perspectiveCorrection`), and
  crops to 1.586:1. Every step is allowed to fail without taking the photo with
  it — a detection that misses gives a centre crop and says so, and never blocks
  somebody from adding their card.
- It downscales before any of that, which is why none of it needs a background
  thread: the stored photo is 640 points wide, so working at twelve megapixels
  would be discarded effort.

### What the photo path must never do

- **No OCR, ever.** The only Vision request in the app finds rectangles. There
  is no text recognition, and no code that extracts a card number, security
  code, expiry date or name. The app has never needed them.
- **No upload.** Photos are written to Application Support next to the wallet
  file. Nothing in the card-art path opens a network connection.
- **No analytics, no logs, no crash reports.** A card photo is the most
  sensitive thing a user of this app will ever hand it.
- The camera is requested contextually, on the "take a photo" tap, never at
  launch. `NSCameraUsageDescription` says what the camera is *not* used for as
  well, because a credit-card app asking for the camera is exactly the prompt a
  careful person declines.

## What the app is allowed to say

`CardArtSource.provenanceLine` and `.shortLabel` own the wording, in CardKit,
where a test checks that the drawn face never describes itself as official,
authentic, exact or genuine.

| Source | Label | Sentence |
|---|---|---|
| `.licensed` | "Official card artwork" | the grant's attribution line |
| `.userPhoto` | "Your card photo" | "Your own photo of this card." |
| `.drawn` | "CardWise representation" | "Drawn by CardWise. Not the bank's artwork — we show that only where we have permission to." |

Do not label artwork official, authentic or exact unless that is true and
documented. And do not use "partner" language anywhere: there are no issuer
partnerships.

VoiceOver gets the same distinction — "CardWise representation of Amex Gold"
rather than "Amex Gold card" — because it is otherwise invisible to a screen
reader.

Beyond those lines, the licensing should be invisible. A person adding their
card does not need to know what a manifest is; they need a wallet that looks
good. The complexity belongs inside the system.

## Attribution

`CardArtLibrary.attributions()` returns a credit line per asset that is
**currently usable** and requires one. Settings shows them. A revoked or lapsed
grant leaves no credit line behind claiming we still have it.

## The interlock

`CardArtLibrary.asset(for:use:asOf:)` is the only supported way to reach an
asset, and it refuses anything unapproved, revoked, lapsed, not yet started or
not covered for that use. That check lives inside the library rather than at
each call site, so a forgotten check in a new view cannot put unlicensed art on
screen.

`CardArtLibrary.match(productID:in:...)` exists so the rules above can be tested
against a list that is not the shipping one — it is **internal**, not public, and
must stay that way. A public overload taking an asset list would be a way around
the registry, which is the one thing this file exists to prevent.
