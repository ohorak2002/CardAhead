# Getting this onto your iPhone from Windows

You do not need to own a Mac, rent a Mac, or sit in front of one. You do need a
Mac to *exist* somewhere, because Xcode — Apple's app-building program — only
runs on macOS and there is no way around that. GitHub's build machines are
Macs, so that part is already solved and already paid for.

The split is:

| Job | Where it happens |
|---|---|
| Write the code | Your Windows PC |
| Turn it into an app | GitHub's Mac, automatically, on every push |
| Put it on your iPhone | Your Windows PC, over a USB cable |

## Once, before the first install

**1. Get a Google Places API key.** Without it the app installs and runs but
registers zero geofences, so there is nothing to test. Steps are in
[places-api.md](places-api.md); it is free and takes about ten minutes.

**2. Put the key into GitHub.** In the repository: Settings → Secrets and
variables → Actions → New repository secret. Name it exactly
`GOOGLE_PLACES_API_KEY`. GitHub hides the value from the build log.

Skip this and the app still builds — it will just say "no place provider is
configured" under Settings → Reminder activity, which is the code being honest
rather than broken.

**3. Install Sideloadly** on Windows, from sideloadly.io. It is the tool that
signs the app with your own Apple ID and copies it to a plugged-in iPhone.

**4. Install iTunes** (the version from Apple's own site, not the Microsoft
Store one). Sideloadly needs the USB drivers that come with it.

## Every time you want a new build on the phone

1. Build it. Either push to `main`, **or** — and this is usually what you
   want — build the branch you are actually working on without merging it:
   GitHub → Actions → CI → **Run workflow** → pick the branch. From a
   terminal that is `gh workflow run ci.yml --ref <branch>`. Wait about five
   minutes.
2. On GitHub: Actions → the latest run → scroll to **Artifacts** →
   download `CardWise-unsigned-ipa`. It arrives as a zip; unzip it to get
   `CardWise-unsigned.ipa`.
3. Plug in the iPhone. Unlock it. Tap **Trust** if asked.
4. Open Sideloadly, drag the `.ipa` in, enter your Apple ID, press Start.
5. On the phone: Settings → General → VPN & Device Management → tap your
   Apple ID → **Trust**. Only needed the first time.

The app now appears on the home screen.

## The seven-day clock

A free Apple ID signs apps for **seven days**. On day eight the app refuses to
open and you repeat the five steps above. Nothing is lost — the wallet and the
event log stay on the phone.

A paid Apple Developer account ($99/year) extends this to a year and unlocks
TestFlight, which installs over the air with no cable. Worth it only once you
know the app is worth carrying around.

## What to actually test, in order

Do these in order. Each one only makes sense if the previous one worked.

**1. Does it think it is running?** Add a card with a bonus category — a dining
card is easiest. Grant Always location, then notifications. Open Settings →
Reminder activity. Within a minute or two of walking about outside it should say
something like "Watching 14 places within 1,800m." If it says "no place
provider is configured", the key did not make it into the build.

**2. Does a geofence fire?** Walk into one of the places it is watching. You do
not know which ones those are, but a busy high street will contain several.
Reminder activity should log "Arrived at <shop>. Waiting 4 minutes to be sure."

**3. Does the reminder arrive?** Stay put for four minutes with the phone
locked and the app closed. A notification should appear naming a card. Tap it —
it should open that card, not the wallet list.

**4. Does walking past *not* fire?** This is the one most likely to be wrong and
the most important. Walk past a watched shop without going in, or go in and
leave inside four minutes. Reminder activity should say "Left <shop> before the
reminder was due. Nothing sent." No notification should arrive.

**5. Do the twenty move with you?** Travel a few kilometres. Reminder activity
should log a new "Watching N places" line. iOS delivers the wake-up that
triggers this after roughly 500m of real travel, so it will not happen on a walk
round the block.

## If something does not work

Everything the geofences do is written to Settings → Reminder activity, because
none of it can be watched happening. Screenshot that screen — it is the entire
diagnostic surface, and it records failures too ("iOS refused to watch X",
"Could not look up nearby shops: ...").

Two known limits worth ruling out before assuming a bug:

- **iOS applies its own delay before reporting an entry**, usually around twenty
  seconds, on top of our four minutes. Walking straight in and out fast will
  legitimately produce nothing.
- **A geofence needs a location fix.** Deep inside a large building with no wifi,
  iOS may not notice the crossing until you come out.
