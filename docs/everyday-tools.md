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

## Plugin review receipt

Applied SwiftUI Expert 5.0.0 (`skills/swiftui-expert-skill/SKILL.md`), Build iOS Apps 0.1.2 (`skills/swiftui-performance-audit/SKILL.md`), and App Design Research 0.1.5 (`skills/app-design-review/SKILL.md`) from the installed plugin cache. Inputs are the user's ChatGPT-generated design references, the prior CardAhead UI, current SwiftUI source, and CI-generated images; no external app research or paid design service was used.

The review focused on three findings:

1. Home's new category selection originally shared a view boundary with monthly ledger calculations. Extracted TodayRecommendation and MonthlyRewardsPanel so changing the purchase type need not rebuild unrelated sections. This is a structural improvement, not a measured performance claim.
2. Nicknames and hidden cards must survive an app restart without changing notification content. Stored them outside Card, isolated their store to the main actor, and added a simulator persistence test. Preferred-card selection uses the existing ranking tie breaker.
3. Dense comparisons need their card identity to remain clear while scrolling and at large text sizes. Repeated the card names alongside values, stacked values at accessibility sizes, and retained native Back and sheet dismissal. Added comparison-selection and explanation-dismissal simulator tests.

Minimum deployment remains iOS 17. CI records its actual iPhone/OS in the run logs. Build iOS Apps' local simulator probe returned `spawn xcrun ENOENT` on Windows, so the existing macOS CI performs runtime checks. Device VoiceOver, Reduce Motion, physical-phone interaction, and minimum-OS runtime testing remain unverified unless separately recorded. A screenshot proves appearance only; the UI tests exercise the stated flows.
