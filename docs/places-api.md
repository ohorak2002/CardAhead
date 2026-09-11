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
   - **Application restriction:** iOS apps, bundle ID `com.example.cardrewards`
     (or whatever `PRODUCT_BUNDLE_IDENTIFIER` is by then).
   - **API restriction:** Places API (New) only.
   - Set a daily quota cap. One user generates roughly one call per few hundred
     metres of travel, minus everything the cache absorbs, so a low cap will
     catch a runaway loop long before it catches real use.

## Building with it

On a Mac, after `xcodegen generate`:

```bash
xcodebuild build -project CardRewards.xcodeproj -scheme CardRewards -destination 'generic/platform=iOS Simulator' GOOGLE_PLACES_API_KEY=your-key-here
```

To avoid passing it every time, put it in a local xcconfig that git ignores, or
set it in the target's build settings in Xcode. Do not commit it, and do not
put it in `project.yml` — that file is checked in.

CI does not set it. The macOS job builds with an empty key on purpose: the app
has to compile and run without one, and a key in a GitHub secret would be a key
in the build log the first time somebody turned on verbose output.

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
