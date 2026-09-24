import SwiftUI
import CardKit

/// The card, held up, before you commit to it.
///
/// **This step did not exist.** Picking a product off a list dropped you
/// straight into a benefits checklist — a screen of toggles and rates asking
/// you to confirm facts about a card you had not yet been shown. That is the
/// order a database would choose. A person wants to see the card and recognise
/// it as theirs, and *then* decide whether the details need correcting.
///
/// So: the card, its name, and two ways forward. Add it, or go and adjust what
/// it earns first. The second is a real door and not a warning — the catalog
/// is right most of the time, and when it is not, the person holding the card
/// is the only authority.
///
/// **The artwork is drawn by `CardFaceView` through the usual resolver**,
/// which means licensed art where a licence is recorded, the user's own
/// photograph where they have taken one, and CardAhead's own rendering
/// otherwise. Nothing on this screen reaches for an issuer's image, and the
/// screen looks finished in all three cases — which is the test of whether the
/// drawn fallback is good enough to ship.
struct CardPreviewView: View {

    let entry: CatalogEntry
    /// Set when this is replacing a card already in the wallet — "I picked the
    /// wrong one" must not leave the wrong one behind.
    var replacing: Card?
    /// Whether this product is already in the wallet. A card can legitimately
    /// be held twice, so this warns rather than forbids.
    var isAlreadyHeld: Bool = false
    /// Tears down the whole add flow, sheet included.
    var onFinish: () -> Void

    @Environment(WalletStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var added = Pulse()
    @State private var hasSettled = false

    private var card: Card { entry.card }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                hero
                details
            }
        }
        .background(InterfacePalette.page)
        .safeAreaInset(edge: .bottom) { actions }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { AddCardProgress(step: 3) }
        }
        .sensoryFeedback(.success, trigger: added)
    }

    // MARK: - The card itself

    /// Large, centred, on its own ground. The one moment in the app where the
    /// card is the entire screen rather than a row in something.
    private var hero: some View {
        VStack(spacing: Metric.roomy) {
            CardFaceView(card: card)
                .frame(maxWidth: 300)
                // A short settle rather than a spring. The card arriving is
                // worth noticing; a card that bounces reads as a prize, and
                // this one costs an annual fee.
                .scaleEffect(hasSettled ? 1 : 0.94)
                .opacity(hasSettled ? 1 : 0)
                .shadow(
                    color: Color.cardAheadNavy.opacity(Metric.liftedShadow.opacity),
                    radius: Metric.liftedShadow.radius,
                    x: 0,
                    y: Metric.liftedShadow.y
                )

            VStack(spacing: 4) {
                Text(entry.issuerFullName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(card.name)
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, Metric.roomy)
        .padding(.top, Metric.loose)
        .padding(.bottom, Metric.loose)
        .frame(maxWidth: .infinity)
        .background(Color.cardAheadCanvas)
        .onAppear {
            guard !hasSettled else { return }
            if reduceMotion {
                hasSettled = true
            } else {
                withAnimation(.easeOut(duration: 0.32)) { hasSettled = true }
            }
        }
    }

    // MARK: - What it earns

    /// Three lines at most, and no controls. This is the "does this look like
    /// my card" screen; the place to argue with the numbers is one tap on.
    private var details: some View {
        VStack(alignment: .leading, spacing: Metric.regular) {
            if isAlreadyHeld {
                HStack(spacing: Metric.tight) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.cardAheadSuccess)
                    Text("This one is already in your wallet. Adding it again is fine if you hold two.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Metric.snug)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Color.cardAheadSuccess.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: Metric.tileRadius, style: .continuous)
                )
            }

            SectionHeader("What it earns")
            RewardSummary(card: card)

            Text(card.annualFeeDollars == 0
                 ? "No annual fee"
                 : "\(CardAheadFormat.money(card.annualFeeDollars)) a year")
                .font(.footnote)
                .foregroundStyle(.secondary)

            // The catalog's own honesty, carried forward rather than hidden
            // behind the "customise" door. Somebody deciding whether this is
            // their card should see what the app admits it cannot model.
            if let first = entry.notModelled.first {
                Label(first, systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Metric.margin)
    }

    // MARK: - The two ways forward

    private var actions: some View {
        VStack(spacing: Metric.snug) {
            Button(replacing == nil ? "Add to Wallet" : "Use this card instead") {
                addToWallet()
            }
            .buttonStyle(.cardAheadPrimary)

            NavigationLink {
                CardBenefitsView(
                    mode: .confirming(entry),
                    replacing: replacing,
                    presentation: .pushed,
                    onFinish: onFinish
                )
            } label: {
                Text("Check what it earns first")
            }
            .buttonStyle(.cardAheadSecondary)
        }
        .padding(.horizontal, Metric.margin)
        .padding(.vertical, Metric.snug)
        .background(.bar)
    }

    /// The same two calls `CardBenefitsView` makes when nothing was corrected.
    ///
    /// **Deliberately not a shortcut around it.** That screen drops the
    /// benefits a person unticked and then adds the card; with nothing
    /// unticked, adding the entry's card *is* the same operation. Routing this
    /// button through the benefits screen invisibly would be worse: a
    /// confirmation step nobody saw is not a confirmation.
    private func addToWallet() {
        added.fire()
        if let replacing {
            store.replace(card.takingWalletPlace(of: replacing))
        } else {
            store.add(card)
        }
        onFinish()
    }
}
