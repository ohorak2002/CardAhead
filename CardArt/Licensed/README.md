# Licensed issuer card artwork

**This directory is empty, and that is the shipping state.** Nothing in it is
licensed yet, because no issuer has granted CardWise anything yet.

## What may go in here

Exactly one thing: an issuer's own card image that CardWise has **written
permission** to display, stored next to the permission that allows it.

```
CardArt/Licensed/
    <issuer>/
        <productID>/
            <assetVersion>/
                card-front.png
                license.json
```

`<productID>` is the catalog product id — `amex-gold`, not "Amex Gold". It has
to match a `CatalogEntry.productID` in
`Packages/CardKit/Sources/CardKit/Data/CardCatalog.swift`, because that is the
only key `CardArtLibrary` matches on.

`<assetVersion>` is the printing of the card — `2026-01`. Issuers redesign; a
redesign arrives as a *new* directory beside the old one rather than
overwriting a file a grant was written against.

## What may never go in here

- Images from an issuer's website, or a screenshot of one.
- Images from a card comparison site, a review site, a press article, Reddit,
  or anywhere else on the internet.
- Anything found through image search.
- AI-generated artwork made to look like an issuer's card design.
- A file somebody "is pretty sure is fine".

If the permission is not in writing and cannot be produced on request, the
artwork does not belong here. The app draws its own card instead, and that is a
perfectly good outcome — see `docs/card-art.md`.

## license.json

One per asset version, next to the image. This is the shape
`CardArtAsset.fromManifest(_:)` decodes, and every field that is missing decodes
to the *refusing* answer: no status means `pendingReview`, no uses means none,
no modification and no cropping. A half-written manifest cannot become a grant.

```json
{
  "id": "example-everyday-2026-01",
  "productID": "example-everyday",
  "issuer": "Example Bank",
  "cardName": "Everyday",
  "assetVersion": "2026-01",
  "imageName": "example-everyday",
  "licence": {
    "affiliateProgramme": {
      "name": "Example Partners",
      "termsURL": "https://example.com/partner-terms"
    }
  },
  "status": "approved",
  "permittedUses": ["walletDisplay", "appDisplay"],
  "effectiveDate": "2026-01-01T00:00:00Z",
  "expiresOn": "2027-01-01T00:00:00Z",
  "modificationAllowed": false,
  "croppingAllowed": true,
  "territory": "US",
  "attributionRequired": true
}
```

Dates are ISO 8601.

`status` is one of `pendingReview`, `approved`, `revoked`. There is deliberately
no `expired` — that is worked out from `expiresOn`, so it cannot be wrong the
day after it lapses.

`permittedUses` is the part most often got wrong. `walletDisplay` and
`appDisplay` are inside the app; `marketing` is websites, social and decks;
`appStore` is the App Store listing's screenshots. **A grant covering one does
not cover the others**, and plenty of brand kits grant the in-app uses and
explicitly withhold the rest. Read the clause, not the headline, and tick only
what it says.

`licence` records where the file came from — which is not the same question as
whether it may be shown today. An asset the issuer definitely emailed us is
still refused while `status` says `pendingReview`.

## Adding one

The full checklist is in [`docs/card-art.md`](../../docs/card-art.md). The short
version: the image goes here *and* into `App/Assets.xcassets` under
`imageName`, an entry goes into `CardArtLibrary.assets`,
`CardArtLibraryTests.testLibraryShipsEmpty` has to be deliberately changed, and
the commit message says which grant the entry rests on.
