# Optional Impact sharing and owner dashboard

The app now has a functioning Supabase Auth/Postgres REST client, durable upload
queue, guarded SQL endpoints and a native owner dashboard. It is **not deployed**
by checking out the repository. Empty configuration leaves sharing unavailable and
owner access denied. Wallets, photos and local Impact remain usable without it.

## Deployment

1. Create a Supabase project you control. Use a separate staging project first.
   Enable email/password authentication and **Confirm email**; configure SMTP,
   the confirmation destination/site URL, rate limits and abuse protection.
2. Run `backend/migrations/001_impact.sql` once in the project's trusted SQL
   editor, as database owner. Do not expose `cardahead_private` in Data API schemas.
   Never run `backend/tests/bootstrap.sql` against Supabase; it is CI-only.
3. Set these GitHub Actions **repository variables** for the IPA job:
   `IMPACT_SERVICE_URL=https://YOUR_PROJECT.supabase.co` and
   `IMPACT_PUBLIC_KEY=YOUR_PUBLISHABLE_OR_ANON_KEY`. These are public client
   configuration. Do not use a service-role key, database password, or secret key.
   Alternatively pass the same Xcode build settings locally. `project.yml` maps
   them to `ImpactServiceURL` and `ImpactPublicKey` in the app's Info.plist.
4. Build and install the app. Open More → Your impact → Impact sharing & account.
   Create your account, verify its email, and sign in. This gives no admin rights.
5. In the trusted Supabase console, independently identify **your verified
   `auth.users.id` UUID**. Provision it using the following SQL, substituting that
   UUID locally in the console. No email, password, UUID or privileged credential
   needs to be committed to this repository.

   ```sql
   insert into cardahead_private.owner_config(singleton, user_id)
   select true, id from auth.users
   where id = 'YOUR-VERIFIED-AUTH-USER-UUID'::uuid
     and email_confirmed_at is not null
   on conflict(singleton) do update set user_id = excluded.user_id;
   ```

   Confirm exactly one row was inserted/updated. No matching verified account
   means no access. There is never a first-user administrator.
6. Reopen Impact sharing. Only a successful server owner check reveals
   **Owner dashboard**. It loads aggregates from `cardahead_dashboard`; invoking
   that endpoint directly still requires the configured, verified owner.
7. Before production, run the staging checks below, review project security
   advisors, restrict operator access, configure database backup retention, and
   publish a privacy policy identifying the operator and Supabase as processor.
   The owner must choose hosting region and retention policy before collecting
   real participants' data.

The existing `GOOGLE_PLACES_API_KEY` GitHub **secret** is independent. The IPA
workflow continues injecting it during archive. A Places key cannot configure
Impact authentication or confer administrator rights.

## Data contract and authorization

Every table is in a private schema, has RLS enabled, and has no client table
grants or policies. Only authenticated users can invoke the narrow public RPCs.
Each RPC checks the authenticated identity; upload additionally locks and checks
that user's current consent epoch. Owner checks join a server-only singleton
configuration row to `auth.users`; user metadata, email claims, roles supplied in
JSON, and local UI flags cannot grant access. Even the owner cannot directly read
raw reports using client credentials. SQL functions use an empty search path and
fully qualified table names.

The export is an allowlist, not a serialization of wallet or ledger objects:
event UUID, optional recommendation UUID, UTC day, known catalog product ID,
category, integer-cent amounts and calculation version. No merchant, address,
coordinates, wallet UUID, custom card name, photo, bank credential or card number.
The server attaches the authenticated account ID. Email belongs to Auth and is
not copied into reporting tables. This is pseudonymous, not anonymous.

Authentication sessions are kept in this device's Keychain. No privileged
credential is shipped. Supabase validates JWTs before PostgREST invokes RPCs;
production token verification is supplied by that service, not a client claim.

## Consent, retries and deletion

- Sharing starts off regardless of local tracking. Creating/signing into an
  account does not opt in. Only newly created eligible reports after consent are
  queued. A separate confirmation explicitly uploads earlier recommendation
  reports still held in the local ledger.
- `impact-sharing.json` atomically persists consent, account binding, epoch,
  pending records and pending privacy actions. Upload batches contain at most 100
  reports. Stable event IDs and a second `(user, recommendation, kind)` uniqueness
  constraint prevent retries from double-counting. Unacknowledged batches remain
  queued. Retry delay grows exponentially to one hour; foregrounding also retries.
- Turning sharing off clears the queue immediately and stops new uploads. An
  already in-flight request can finish; serialized revocation follows it. If
  offline, server revocation remains pending and is clearly shown. The user must
  reconnect while signed in. Re-enrollment is blocked until it completes.
- “Delete previously shared records” disables sharing and durably requests
  deletion. Upload and deletion lock the same participant row, so an old request
  cannot recreate deleted records after deletion finishes. Deletion affects only
  the authenticated user's reports. It leaves the authentication account and a
  disabled consent row. Provider backups expire under the operator's retention
  policy; the app does not claim to purge backups immediately.
- Switching local tracking off erases local Impact and stops sharing. It does
  not silently delete previously shared data. “Erase everything” additionally
  requests shared-record deletion. Offline deletion cannot finish until connected.
- Do not sign out or uninstall with a pending deletion; the UI explains pending
  actions and prevents sign-out until they finish. Account removal, if desired,
  can be performed by the operator in Supabase Auth; foreign keys cascade reports.

## Honest metrics

“Currently sharing” counts enabled consent rows. “Users reporting” applies to the
selected date range. Acted-on recommendations are user confirmations, not proof of
a transaction. Purchases are volunteered amounts. Rewards are estimates using
frozen recommendation assumptions and user point valuations; additional rewards
are a separate comparison with the best other eligible wallet card at suggestion
time. Missing baselines stay null, and the dashboard shows coverage. Received
credits/rewards come from the user recording an offer redemption, are independent
of estimate totals, and are never described as verified or savings.

Trends group by UTC day. Category and product breakdowns exclude unnecessary
merchant details. “Unknown” buckets are intentional. Data represents voluntary,
incomplete participation, not the whole installed user population. Account annual
fees, interest, and unconfirmed future welcome bonuses are not savings figures.

## Verification boundary

`backend/tests/authorization.sql` runs against real PostgreSQL 16 in GitHub CI,
using isolated Auth role fixtures. It checks anonymous and ordinary-user denial,
forged role/email/metadata claims, missing-owner denial, unverified-owner denial,
configured-owner access, private-table denial, consent, input validation,
duplicate prevention, deletion isolation, late-upload rejection and null baselines.
Those tests do **not** constitute a production deployment or test hosted Auth.

Before launch, test on staging with two verified accounts and an anonymous client:
email confirmation; sign-in/token refresh; owner and nonowner REST access; forged
and expired JWT rejection; airplane-mode retry; killing/relaunching with queued
data; duplicate submission; opting out during upload; deletion during upload;
account switch; Keychain persistence; reinstall; server failure; and revoking the
owner configuration while the dashboard is open. None requires real card data.
