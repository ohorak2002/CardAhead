# CardWise privacy policy

The policy is published at
**https://ohorak2002.github.io/portfolio/cardwise/privacy/**, with the support
page at https://ohorak2002.github.io/portfolio/cardwise/support/.

The source is in the portfolio repository (`ohorak2002/portfolio`), under
`cardwise/privacy/index.html` and `cardwise/support/index.html`. That is the one
copy; this file used to hold a draft and was replaced by this pointer so the two
could not drift apart.

Both addresses are baked into the app through `PRIVACY_POLICY_URL` and
`SUPPORT_URL` in `project.yml`, and shown in More › Privacy & legal. Shipped
builds keep whatever address they were built with, so if the pages ever move,
leave the old addresses redirecting.

Keep the policy in step with `App/Views/PrivacyAndLegalView.swift` and
`App/PrivacyInfo.xcprivacy`. If the optional Impact sharing service is ever
switched on for a release, the policy needs a section for it first: what is
uploaded, where it is stored, for how long, and how to delete it and the account.
