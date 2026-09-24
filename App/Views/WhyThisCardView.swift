import SwiftUI
import CardKit

/// What each card would earn here, the caveats behind the answer, and how the
/// ranking arrives at it. Reached from the More tab.
///
/// The "where you are" controls at the top are a bench, not a stand-in: the
/// geofence exists and does this on its own, and these are how the ranking
/// gets exercised without walking into a shop.
struct WhyThisCardView: View {

    @Environment(WalletStore.self) private var store

    @State private var category: SpendingCategory = .dining
    @State private var merchantName = ""
    @State private var confidence: MerchantConfidence = .exact
    @State private var isTraveling = false
    @State private var isAbroad = false

    private var context: PurchaseContext {
        PurchaseContext(
            category: category,
            merchantName: merchantName,
            confidence: confidence,
            isTraveling: isTraveling,
            isAbroad: isAbroad,
            date: Date()
        )
    }

    var body: some View {
        List {
            whereYouAreSection
            if let recommendation = store.recommendation(for: context) {
                Section { RecommendationReason(recommendation: recommendation, contextName: category.displayName) }
                rankingSection(recommendation)
                if !recommendation.best.caveats.isEmpty {
                    caveatsSection(recommendation)
                }
            } else {
                Section {
                    Text("Add a card and the ranking appears here.")
                        .foregroundStyle(.secondary)
                }
            }
            howItWorksSection
        }
        .navigationTitle("Why this card")
        .navigationBarTitleDisplayMode(.inline)
        // The floating tab bar draws over the end of a scroll view rather
        // than shortening it, so the last section was half-hidden behind it.
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 60) }
    }

    // MARK: - Where you are

    private var whereYouAreSection: some View {
        Section {
            Picker("Buying", selection: $category) {
                ForEach(sortedCategories, id: \.self) { category in
                    Text(category.displayName).tag(category)
                }
            }
            TextField("At", text: $merchantName)
            Picker("How sure are we?", selection: $confidence) {
                Text("The exact shop").tag(MerchantConfidence.exact)
                Text("Only the type").tag(MerchantConfidence.categoryOnly)
            }
            .pickerStyle(.segmented)
            Toggle("Away from home", isOn: $isTraveling)
            Toggle("In another country", isOn: $isAbroad)
        } header: {
            Text("Where you are").textCase(nil)
        } footer: {
            Text("Choose a purchase type to explore the recommendation for your wallet. The map uses the same ranking for nearby places.")
        }
    }

    private var sortedCategories: [SpendingCategory] {
        SpendingCategory.allCases
            .filter { $0 != .base }
            .sorted { $0.displayName < $1.displayName } + [.base]
    }

    // MARK: - What each card would earn

    private func rankingSection(_ recommendation: Recommendation) -> some View {
        Section {
            ForEach([recommendation.best] + recommendation.alternates) { score in
                scoreRow(score, isBest: score.id == recommendation.best.id)
            }

            if let nudge = recommendation.activationNudge {
                Label(nudge.sentence, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Color.cardAheadWarning)
            }
        } header: {
            Text("What each card would earn").textCase(nil)
        } footer: {
            Text("Cents back for every dollar you spend here, after point value, any fee abroad, and any open signup bonus.")
        }
    }

    private func scoreRow(_ score: CardScore, isBest: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(score.card.displayName)
                    .font(.subheadline.weight(isBest ? .bold : .regular))
                if score.needsActivation {
                    Text("not switched on")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.cardAheadWarning)
                }
                if score.isCapExhausted {
                    Text("bonus used up")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.cardAheadWarning)
                }
                Spacer(minLength: 8)
                Text(String(format: "%.2f¢", score.total))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(isBest ? Color.accentColor : .secondary)
            }
            Text(score.reason)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Worth knowing

    private func caveatsSection(_ recommendation: Recommendation) -> some View {
        Section {
            ForEach(recommendation.best.caveats, id: \.self) { caveat in
                Text(caveat)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Worth knowing").textCase(nil)
        }
    }

    // MARK: - How the ranking works

    private var howItWorksSection: some View {
        Section {
            Text("""
                 Everything becomes one number, so the pieces can be compared. A bonus you have already used \
                 up does not count. A rotating bonus nobody switched on does not count. A fee abroad is taken \
                 off. And an open signup bonus is spread across the spend still needed — $200 of cash back \
                 with $1,200 left to spend is 16¢ on the dollar, which is why it beats every 5% category \
                 until it is earned.
                 """)
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("How the ranking works").textCase(nil)
        }
    }
}

#Preview {
    NavigationStack {
        WhyThisCardView()
    }
    .environment(WalletStore.previewStore())
}
