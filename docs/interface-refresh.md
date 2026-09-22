# CardWise interface refresh — September 19, 2026

Requested direction: the supplied navy / blue / white iPhone references, with
an emphasis on user friendliness and recognizable issuer logos in Add a Card.
Text embedded in the reference images is not a feature specification. No admin
dashboard, new recommendation policy, or notification redesign is included.

## Interface

- Home: navy atmospheric header, optional name, a real nearby-opportunity count,
  a layered preview of existing card faces, a compact recommendation, and shortcuts.
- Wallet: compact light header, recognizable full card faces, and a name / best-use
  panel. Tap a card to expand its existing reward summary and controls.
- Benefits: light header, explicit active-benefit count, and blue-washed category tiles.
- Map: readable title, search field, and filters on a light surface. Existing map,
  place photos, results, camera actions, geofences, and filter behavior are preserved.
- Add a Card: local bank logo assets, easy-to-tap bank rows, and Bank / Card /
  Review progress. Search, duplicate guidance, and manual entry still work.
- Impact: lighter surfaces and refined presentation of the existing measured values.

`App/Theme/CardWiseInterface.swift` defines adaptive presentation roles for the
changed screens. Existing shared card-art colors, category palettes, notification
badge rendering, policies, permission prompts, and notification settings are unchanged.
Native tabs and navigation remain native. Content retains Dynamic Type and VoiceOver.

## Issuer identifiers

The user explicitly requested the banks' actual logos in the picker. This supersedes
the earlier monogram-only visual preference for that picker; it does not change
card-face artwork or the card-art resolver. The assets identify issuers alongside
their names. They are bundled, never downloaded when someone opens the picker.
Unknown issuers retain the monogram fallback. No issuer endorsement is claimed.

Sources retrieved September 19, 2026 from the issuers' own home-page asset links:

| Asset | Source |
|---|---|
| American Express | https://www.aexp-static.com/cdaas/one/statics/axp-static-assets/1.8.0/package/dist/img/logos/dls-logo-bluebox-solid.svg |
| Chase | https://www.chase.com/etc/designs/chase-ux/favicon-152.png |
| Capital One | https://www.capitalone.com/assets/shell/apple-touch-icon.png |
| Citi | https://www.citi.com/content/dam/cfs/uspb/usmkt/cbol-homepage/en/static/images/citilogo-skelheader-compressed.png |
| Discover | https://www.discover.com/content/dam/discover/en_us/credit-cards/card-acquisitions/grey-redesign/global/images/icons/icon-discover-logo-136-23.png |
| Wells Fargo | https://www17.wellsfargomedia.com/assets/images/icons/apple-touch-icon_180x180.png |

Source provenance is not a representation of a trademark license. These remain the
respective issuers' marks and are separate from the licensed-card-art registry.

## Verification

Run the repository's brace scan and diff checks locally, then the complete existing
CI workflow on the feature branch: CardKit tests, iOS simulator build, simulator
screenshots in light/dark/large text, and the unsigned IPA archive. Windows cannot
compile the SwiftUI app. The build and photographs, not static checks, determine
whether the change is ready to hand off.
