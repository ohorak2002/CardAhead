import SwiftUI
import CardKit

/// The second and only other screen. Everything that is not the wallet lives
/// here: what each card would earn, the caveats behind the answer, and how the
/// ranking arrives at it.
///
/// The "where you are" controls at the top stand in for the geofence until
/// build step 4 lands. They move behind a debug flag once region monitoring is
/// doing this on its own.
struct WhyThisCardView: View {

    @Environment(WalletStore.self) private var store

    @State private var category: SpendingCategory = .dining
    @State private var merchantName = "ABC Restaurant"
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
            Text("Standing in for the geofence that will do this on its own.")
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
                Label(nudge, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
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
                        .foregroundStyle(.orange)
                }
                if score.isCapExhausted {
                    Text("bonus used up")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
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
