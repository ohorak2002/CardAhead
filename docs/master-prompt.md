# Master Prompt — Credit Card Rewards Reminder App (iOS)

Copy everything below into Claude Code.

---

## Project

Build an iOS app (Swift / SwiftUI) that reminds the user which of their credit cards to pay with, based on where they are or what they're buying. The problem: people carry multiple rewards cards and forget which one earns bonus cash back at the moment of purchase.

**Hard constraint:** Apple does not expose the Apple Pay double-tap card picker to third-party apps. We cannot inject a suggestion into that sheet. All nudges must arrive as a local notification *before* the user reaches for their phone to pay.

---

## Core architecture — three detection engines

### 1. Physical location (primary engine)

Use **Core Location region monitoring** (`CLCircularRegion` + `startMonitoring(for:)`), NOT continuous GPS polling or a manual dwell timer.

Why: iOS's location daemon watches the geofence itself, so the app gets `didEnterRegion` callbacks even when backgrounded or terminated, at a fraction of the battery cost of `startUpdatingLocation`.

Implementation rules:
- Request **Always** authorization, with a pre-permission explainer screen stating plainly what the app does with location and that location never leaves the device except as an anonymized merchant lookup.
- Radius: **100m minimum** (Apple's recommendation). Urban GPS error is 20–50m; a tighter radius misfires.
- **20-region hard limit per app.** Do not attempt to geofence every merchant. Instead:
  - Maintain a server/local database of nearby merchants.
  - On significant location change, re-register the 20 nearest relevant merchants (relevant = maps to a bonus category on a card the user actually owns).
  - Evict and re-register as the user moves.
- On `didEnterRegion`, start a **3–5 minute in-app confirmation delay** before notifying. This kills drive-by and walk-past false positives without the long lag of a pure dwell-time model. If `didExitRegion` fires before the delay elapses, cancel the notification.
- On `didExitRegion` after a notification fired, optionally log the visit for the "did you use the right card?" feedback loop (see below).

### 2. Travel detection

Use **significant-location-change monitoring** (`startMonitoringSignificantLocationChanges`) as a coarse, low-power layer.

- If the user's location moves more than ~50 miles from their registered home city, enter "travel mode."
- In travel mode, prioritize travel-category cards for all suggestions and surface travel-specific perks (no foreign transaction fee, lounge access, rental car insurance).
- Also geofence airports and hotel chains as normal regions when the user is in travel mode.

### 3. Online purchases (separate engine — location cannot detect this)

There is no coordinate for browsing Amazon. Do not try to force this into the geofencing model.

Ship this as a **Safari Web Extension** bundled with the app:
- Reads only the current page's domain (not page content, not form fields, not credentials).
- Matches domain against a merchant→category map (amazon.com → online shopping, delta.com → travel, instacart.com → grocery).
- On a checkout-page URL pattern, shows a small non-blocking banner: which card to use and why.
- Fallback if the user declines the extension: an in-app "I'm buying from…" quick-select with the top 20 merchants.

---

## Card recommendation ranking

When multiple cards qualify for the same category, rank by:
1. Highest effective earn rate for that category (convert points to cents-per-point using a user-editable valuation, default 1.0¢).
2. Active quarterly rotating bonus, if the category matches this quarter.
3. Unmet welcome-bonus spending requirement — if a card has an open signup bonus, weight it heavily until met.
4. Spending cap remaining — deprioritize a card whose category cap is exhausted (e.g. Amex Blue Cash grocery cap).
5. Tiebreak: user's manually pinned preference.

The notification names **one** card. Show alternates only when the user taps in.

---

## Example card benefits to seed the database

Model the data so each card holds an array of category rules with rate, cap, and expiry. Seed with real, well-known structures:

| Card | Benefit |
|---|---|
| Chase Freedom Flex | 5% on rotating quarterly categories (up to $1,500/qtr), 3% dining, 3% drugstores, 1% base |
| Chase Sapphire Preferred | 3x dining, 2x travel, 5x travel booked through Chase, 1x base |
| Discover it | 5% rotating quarterly (up to $1,500/qtr), 1% base, first-year cashback match |
| Amex Blue Cash Preferred | 6% U.S. supermarkets (up to $6,000/yr), 6% streaming, 3% transit, 3% U.S. gas, 1% base |
| Amex Gold | 4x restaurants, 4x U.S. supermarkets (up to $25,000/yr), 3x flights, 1x base |
| Citi Double Cash | 2% flat on everything — the fallback when no bonus applies |
| Capital One Savor | 3% dining, 3% entertainment, 3% streaming, 3% grocery, 1% base |
| Wells Fargo Active Cash | 2% flat on everything |
| Costco Anywhere Visa | 4% gas (up to $7,000/yr), 3% restaurants and travel, 2% Costco, 1% base |

Also model **non-earn perks** surfaced in travel mode: no foreign transaction fee, trip delay insurance, rental car CDW, lounge access, annual travel credits.

Include a **quarterly rotating category** system with an activation reminder — Chase Freedom and Discover both require manual activation each quarter and users routinely forget. This is a genuine differentiator.

---

## Merchant → category mapping

Reverse-geocode the geofence trigger to a specific business using the **Google Places API** (or Foursquare). Map the returned place type to a spending category. Cache aggressively; do not call the API on every trigger.

Handle these edge cases explicitly:
- A restaurant inside a mall or a food hall — indoor GPS won't resolve the specific unit. If confidence is low, send a category-level notification ("Dining nearby — use Amex Gold for 4x") rather than naming the wrong business.
- Gas stations with attached convenience stores may code as either gas or grocery depending on the merchant's MCC. Note the ambiguity in the card detail view.
- Warehouse clubs (Costco, Sam's) often do not code as grocery. Flag these as exceptions in the data model.

---

## UI

Reference screenshot attached: Apple Wallet's stacked card layout. Match that interaction model.

- **Home screen:** vertically stacked cards, overlapping so only the top strip of each is visible, tap to expand a card to full height and reveal its category rules, caps, and current quarter status. Drag to reorder. This is the primary navigation — no tab bar clutter.
- Cards render as accurate visual replicas of the real card art (issuer colors and logos), so recognition is instant and matches what's in the user's physical wallet and in Apple Wallet.
- **Notification tap** opens directly to the recommended card, expanded, with the reason stated in one line: "3% dining at ABC Restaurant."
- **Add card flow:** search by issuer and card name, pull benefit rules from the seeded database, let the user edit.
- **Empty state:** an invitation to add the first card, not an apology.
- Respect Dynamic Type, reduced motion, and dark mode. Motion only in response to user action — card expansion and reorder. No decorative animation.

Copy is plain and active. "Use Amex Gold here" not "Optimize your rewards potential."

---

## Feedback loop

After a notification, offer a single-tap "used it" / "didn't" on the next app open. Use this to:
- Suppress geofences the user consistently ignores.
- Learn which merchants are false positives and shrink or drop those regions.
- Never send more than one notification per merchant per day, or more than ~4 per day total.

---

## Privacy

- Location processed on-device wherever possible. Merchant lookups send coordinates only, no user identifier.
- No transaction data, no bank account linking in v1 — that requires Plaid and a whole compliance surface. Card benefits are user-entered or database-seeded.
- Ship a plain-language privacy screen before the Always-location prompt. The permission ask is the biggest drop-off point in the funnel; earn it.

---

## Build order

1. Data model for cards, categories, caps, rotating quarters.
2. Wallet-style stacked card UI with add/edit/reorder.
3. Recommendation ranking engine (testable in isolation, no location needed).
4. Region monitoring + notification pipeline with the confirmation delay.
5. Places API merchant resolution.
6. Significant-location-change travel mode.
7. Safari extension for online.

Start with 1–3 and show me before moving on.
