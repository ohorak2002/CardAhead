# Everyday tools

This build implements the five UI improvements confirmed on September 20, 2026.

- Home's Today section offers a purchase-category picker and its actual wallet recommendation, nearby opportunities, the next recorded deadline, and this month's estimated extra rewards. An optional user-set goal is a rewards target, not a spending target.
- Recommendations explain the existing engine score and offer a contextual comparison sheet. No invented benefit balances, fee savings, or new ranking formulas.
- The Benefits timeline shows current and published future rotating quarters, recorded activation deadlines, and open signup deadlines. Quarter-end labels use the last eligible calendar day; the engine retains its exclusive midnight cutoff. Credits without a known reset date are explicitly undated.
- Organize cards is available from the Wallet header. Existing native reordering remains available. Nicknames and hidden faces are stored separately in organization.json and never change notification content or card artwork. Hidden cards still participate in recommendations and benefits. An explicit preferred-card choice uses the existing tie breaker.
- Compare cards shows two actual wallet cards side by side, with current ongoing earning rates, point-valued estimates, annual fees, foreign transaction fees, and recorded credits. At accessibility text sizes, each row stacks the named cards vertically.

Organization persistence is atomic and updates observable state only after a successful write. A corrupt saved preference file is retained and protected from overwriting. Erase everything includes the new preferences. The wallet schema and existing notification pipeline are unchanged.

Monthly figures use confirmed estimates recorded in the current calendar month from the retained impact ledger. They exclude future entries, other months, and unpriced suggestions. The current impact ledger retention limit still applies; this is not a bank transaction statement.

CI adds Today, timeline, comparison, organization and explanation captures, including dark and largest-text variants. The example signup bonus and nickname are fabricated screenshot fixtures under DemoSeed only and never enter a real wallet or catalog.

Widgets, Watch, scanning, transaction import, and onboarding are outside this five-item build. They were discussed earlier but are not implemented by this change.
