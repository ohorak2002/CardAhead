# Card artwork

The app never sees a card number, so the card's face is how a user tells their
cards apart. Getting that face right matters more here than it would in most
apps. This is how to do it without getting the app pulled.

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

`CardArtSource.resolve(for:)` picks the first that applies:

| Source | When it applies | Licence |
|---|---|---|
| `.licensed` | We hold a grant for that exact issuer and card | Recorded per asset |
| `.userPhoto` | The user photographed their own card | Theirs, always fine |
| `.drawn` | Everything else — the default | Ours |

The drawn face is not a placeholder to be embarrassed about. It uses the real
ISO/IEC 7810 ID-1 proportion, a material finish, an EMV chip and the
contactless mark, which is most of what makes a card look like a card.

## Adding a licensed asset

`CardArtLibrary.assets` ships empty, and there is a test asserting that it
stays empty. **That test failing is the point** — it forces a deliberate
decision rather than a quiet commit.

Before adding an entry, all of these must be true:

1. **You have the grant in writing.** An email from the issuer's brand or
   partnerships team, or acceptance into a card-marketing programme whose
   terms explicitly cover displaying card imagery in an app.
2. **The grant covers this use.** Many brand kits permit editorial or
   comparison use but not "display as the user's own card in a wallet
   interface". Read the clause, not the headline.
3. **You can produce it on request.** Store the email or terms PDF somewhere
   the whole team can find, and put its identifier in the `reference` field.
4. **You set a `reviewBy` date.** Grants get withdrawn and programmes change.
   An asset past its review date stops being drawn automatically.

Then:

```swift
public static let assets: [CardArtAsset] = [
    CardArtAsset(
        id: "example-everyday-2026",
        issuer: "Example Bank",          // must match Card.issuer exactly
        cardName: "Everyday",            // must match Card.name exactly
        imageName: "example-everyday",   // asset catalog entry
        licence: .affiliateProgramme(
            name: "Example Partners",
            termsURL: "https://example.com/partner-terms"
        ),
        reviewBy: Calendar.current.date(byAdding: .year, value: 1, to: .now)
    )
]
```

Update the test to assert the expected count instead of emptiness, and say in
the commit message which grant each entry rests on.

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

Do not use: images scraped from issuer websites, comparison sites, press
kits you were not granted, or anything found through image search.

## Attribution

`CardArtLibrary.attributions` returns a credit line per licensed asset. The
Settings screen shows them. Some grants require visible attribution; showing it
always is simpler than tracking which ones do.

## The interlock

`CardArtLibrary.asset(issuer:cardName:)` is the only supported way to reach an
asset, and it refuses anything unlicensed or past review. That check lives
inside the library rather than at each call site, so a forgotten check in a new
view cannot put unlicensed art on screen.
