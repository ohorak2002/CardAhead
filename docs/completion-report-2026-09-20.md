# CardWise audit delivery

## Changes delivered

- Audited all nine U.S. catalog products; corrected restricted earning, Costco gas and warehouse rewards, public credits, and unsupported rotating/introductory assumptions. [Issuer audit and remaining uncertainty](card-data-audit-2026-09-20.md).
- Separated catalog terms, personal adjustments, and personal offers. Product identities and old wallet fields survive edits. Individual restore preserves reported cap usage; catalog review preserves personal changes.
- Added four-step offer creation from Benefits and card details, editing, disabling, deletion, enrollment confirmation, limits, exact merchant matching and reported redemption. Saving does not enroll with an issuer. Unknown eligibility/amount/stacking remains conditional.
- Enlarged the Home wordmark; replaced the Benefits emoji grid with earning bars grouped by currency, exact terms and honest cap-usage states.
- Implemented persistent All/None/custom map filters, legacy migration, cancellation and stale-result rejection, clearer search scope and no provider call for empty categories.
- Corrected cap-crossing estimates, froze historical assumptions, and added “I used this card” to place details for optional Impact reporting.
- Implemented separate opt-in cloud sharing, durable retries, deduplication, revocation/deletion, verified authentication, server-authorized owner aggregates and a native dashboard. This is implemented but not deployed.

## Owner access and deployment

Follow [the exact deployment runbook](impact-backend.md): create a Supabase project with email confirmation, apply `backend/migrations/001_impact.sql`, configure the public `IMPACT_SERVICE_URL` and `IMPACT_PUBLIC_KEY` build variables, create and verify your account, and provision its immutable UUID in the server-only owner configuration. Then open More → Your impact → Impact sharing → Owner dashboard. Ordinary users cannot grant themselves owner access; missing configuration denies access.

The Places API key is independent of Impact credentials. No privileged backend key belongs in the app.

## Verification and IPA

- [CI build 119](https://github.com/ohorak2002/CardWise/actions/runs/35547710333), app source commit `bf91903`: **506 CardKit tests passed**, iOS simulator build passed, real-device archive/unsigned IPA passed.
- [Backend authorization CI](https://github.com/ohorak2002/CardWise/actions/runs/35547753843), commit `83b1a90`: PostgreSQL tests passed, including anonymous/ordinary/forged-owner denial, verified owner access, consent, null epoch rejection, duplicate prevention and deletion isolation.
- Downloaded `artifacts/build-119/CardWise-unsigned.ipa`. Inspected the packaged Info.plist and confirmed the configured Google Places key is present without printing it. The adjacent verification JSON records build, size and SHA-256.
- Earlier simulator screenshots were reviewed for normal, Dark Mode and largest text Home/Benefits. Latest expanded screenshots and five UI flow tests are still running at handoff; their results are not claimed as passed. Small-device and final visual review remain pending.

## Remaining limitations

The IPA is unsigned and needs Sideloadly/your Apple signing identity to install; see [iPhone instructions](testing-on-your-iphone.md). Key presence does not prove live API quota/restrictions or geofence delivery. Background location, notifications, VoiceOver and actual device behavior still require an iPhone.

Impact is not live until externally configured. Hosted Auth, offline/relaunch/privacy races and production token rejection need staging integration checks. No mock dashboard is represented as deployed.

Capital One's current page and Discover's quarter categories remain unverified. Issuer coding, enrollment and received rewards cannot be independently verified. Reported usage may be incomplete; UTC calendar periods and exact-name matching have the limitations described in the audit. Estimates are distinct from received rewards and incremental value is unknown when no comparison baseline exists.
