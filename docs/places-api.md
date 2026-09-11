# Wiring up the Places API

Without a key the app runs with `EmptyMerchantSource`: every other part of the
geofencing works, but no region is ever registered, because there is nowhere to
get a shop from. Settings > Reminder activity says so in as many words. This is
the deliberate default — a key is a billable secret and does not belong in a
public repository.

## What the app expects

`PlacesProvider` reads `GooglePlacesAPIKey` out of the app's Info.plist. That
value comes from the `GOOGLE_PLACES_API_KEY` build setting, declared empty in
`project.yml` and substituted at build time. Nothing else reads it, and it is
never written to disk by the app.

## Getting a key

1. In the Google Cloud console, create a project and enable **Places API (New)**
   — not the legacy Places API. The endpoint this app calls is
   `places.googleapis.com/v1/places:searchNearby`, which only the new one serves.
2. Create an API key.
3. Restrict it, which matters more than usual because this key ships inside an
   app anyone can unzip:
   - **API restriction:** Places API (New) only. Always do this one.
   - **Quota cap.** One user generates roughly one call per few hundred metres
     of travel, minus everything the cache absorbs, so a low daily cap will
     catch a runaway loop long before it catches real use.
   - **Application restriction:** iOS apps, bundle ID `com.ohorak.cardrewards`
     (or whatever `PRODUCT_BUNDLE_IDENTIFIER` is by then). Leave this off while
     sideloading for testing — a sideload tool may rewrite the bundle ID, and a
     restriction that no longer matches fails every lookup with a permission
     error that looks nothing like its cause. Turn it on before release.

## Building with it

On a Mac, after `xcodegen generate`:

```bash
xcodebuild build -project CardRewards.xcodeproj -scheme CardRewards -destination 'generic/platform=iOS Simulator' GOOGLE_PLACES_API_KEY=your-key-here
```

To avoid passing it every time, put it in a local xcconfig that git ignores, or
set it in the target's build settings in Xcode. Do not commit it, and do not
put it in `project.yml` — that file is checked in.

## In CI

The two build-checking jobs deliberately build with an empty key: the app has to
compile and behave sensibly without one, and that is worth checking on every
push.

The `ipa` job, which produces the installable app for sideloading, uses a
repository secret named `GOOGLE_PLACES_API_KEY` if one exists and an empty
string if not. GitHub masks a secret's value everywhere it appears in a log, so
this is a reasonable place to keep it. The repository itself is not — that is
what this whole arrangement exists to avoid.

See [testing-on-your-iphone.md](testing-on-your-iphone.md) for where that
artifact goes next.

## What gets called, and how often

Not on arrival. The Places call happens when the twenty geofences are redrawn —
roughly once per significant location change, which iOS delivers after a few
hundred metres of travel. By the time somebody walks into a shop, that shop's
name and category are already inside the registered region and on disk, so the
reminder needs no network and no time.

On top of that, `MerchantCache` snaps each lookup to a 250m grid and keeps the
answer for a week, bounded to 40 squares, least-recently-used first. A commute
walked twice a day costs a handful of calls in the first week and almost none
after that.

## Why Google and not Foursquare

`MerchantCategoryMap` was written against Google's type vocabulary —
`grocery_or_supermarket`, `meal_takeaway`, `gas_station` — before any of this
existed, and the Safari extension's domain map sits beside it. Foursquare would
mean a second category mapping to keep correct alongside the first, and two
mappings for one concept is how the wrong one gets edited.
