import SwiftUI

/// What CardWise does with data, what its recommendations are and are not, and
/// who it is not affiliated with — in the app, where App Review and a careful
/// user both look for it.
///
/// **The summary is here in full, not only behind a link.** A web page can be
/// down, moved or never published; this cannot. The hosted policy and support
/// pages are linked as well when the build carries their addresses
/// (`PRIVACY_POLICY_URL` / `SUPPORT_URL` in `project.yml`), and the rows are
/// absent rather than broken when it does not — a dead link is exactly what
/// App Review taps first.
///
/// Every sentence here must stay true of the code. If a new network call, SDK
/// or stored field is added, this screen, the live policy page (portfolio
/// repo, `cardwise/privacy/index.html`) and
/// `App/PrivacyInfo.xcprivacy` change in the same commit.
struct PrivacyAndLegalView: View {

    var body: some View {
        List {
            Section {
                Label("Your cards, card photos, reminder history and Impact record are stored only on this iPhone.", systemImage: "iphone")
                Label("CardWise never asks for, reads or stores a card number, security code, expiry date or bank login.", systemImage: "creditcard")
                Label("To find shops nearby, your position — and anything you type in the map's search — is sent to Google Places. Address suggestions come from Apple Maps. No name, account or card details go with either.", systemImage: "location")
                Label("No advertising, no tracking across apps, and no analytics service.", systemImage: "hand.raised")
                Label("Erase everything in Settings deletes all of it from this iPhone. So does deleting the app.", systemImage: "trash")
            } header: {
                Text("Your data").textCase(nil)
            } footer: {
                Text("Optional Impact sharing, where a build offers it, is off until you create an account and switch it on, and uploads only the fields listed on its own screen.")
            }

            Section {
                Text("CardWise suggests which of your own cards is likely to earn the most, using published card terms and the values you set. It is for information only and is not financial, credit or tax advice. Rates, caps and offers change and can be wrong here — your card issuer's terms always decide what you actually earn.")
                    .font(.subheadline)
            } header: {
                Text("Recommendations are estimates").textCase(nil)
            }

            Section {
                Text("CardWise is independent and is not affiliated with, endorsed by or sponsored by any bank, card issuer or card network. Card and issuer names are used only to identify the cards you hold.")
                    .font(.subheadline)
            } header: {
                Text("Not affiliated").textCase(nil)
            }

            if privacyPolicyURL != nil || supportURL != nil {
                Section {
                    if let privacyPolicyURL {
                        Link(destination: privacyPolicyURL) {
                            Label("Full privacy policy", systemImage: "doc.text")
                        }
                    }
                    if let supportURL {
                        Link(destination: supportURL) {
                            Label("Help and support", systemImage: "questionmark.bubble")
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Privacy & legal")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var privacyPolicyURL: URL? { Self.configuredURL("PrivacyPolicyURL") }
    private var supportURL: URL? { Self.configuredURL("SupportURL") }

    /// An https address from Info.plist, or nil. XcodeGen substitutes an unset
    /// build setting as an empty string, which must read as "not configured".
    static func configuredURL(_ key: String) -> URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "https", url.host != nil
        else { return nil }
        return url
    }
}

#Preview {
    NavigationStack { PrivacyAndLegalView() }
}
