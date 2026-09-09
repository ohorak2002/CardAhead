import SwiftUI
import CardKit

/// A hand-driven stand-in for the geofence, so the ranking can be seen and
/// argued with before any location code exists. It renders the exact strings a
/// notification would carry, plus the full ranking behind the one card named.
///
/// This screen is scaffolding for build steps 1 to 3. It comes out, or moves
/// behind a debug flag, once region monitoring lands.
struct EngineWorkbenchView: View {

    @Environment(WalletStore.self) private var store
    @Environment(\.dismiss) private var dismiss

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
        NavigationStack {
            List {
                situationSection
                if let recommendation = store.recommendation(for: context) {
                    notificationSection(recommendation)
                    alternatesSection(recommendation)
                } else {
                    Section {
                        Text("Add a card first.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Try it")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var situationSection: some View {
        Section("Where you are") {
            Picker("Category", selection: $category) {
                ForEach(SpendingCategory.allCases, id: \.self) { category in
                    Text(category.displayName).tag(category)
                }
            }
            TextField("Merchant", text: $merchantName)
            Picker("Confidence", selection: $confidence) {
                Text("Exact business").tag(MerchantConfidence.exact)
                Text("Category only").tag(MerchantConfidence.categoryOnly)
            }
            .pickerStyle(.segmented)
            Toggle("Travelling", isOn: $isTraveling)
            Toggle("Abroad", isOn: $isAbroad)
        }
    }

    private func notificationSection(_ recommendation: Recommendation) -> some View {
        Section("What the notification would say") {
            VStack(alignment: .leading, spacing: 6) {
                Text(recommendation.headline)
                    .font(.headline)
                Text(recommendation.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)

            if let nudge = recommendation.activationNudge {
                Label(nudge, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if let perks = recommendation.travelPerkSummary {
                Label(perks, systemImage: "airplane")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(recommendation.caveats, id: \.self) { caveat in
                Text(caveat)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func alternatesSection(_ recommendation: Recommendation) -> some View {
        Section {
            ForEach([recommendation.best] + recommendation.alternates) { score in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(score.card.displayName)
                            .font(.subheadline.weight(score.id == recommendation.best.id ? .semibold : .regular))
                        Text(score.reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Text(String(format: "%.2f¢", score.total))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("Everything else, in order")
        } footer: {
            Text("Cents earned per dollar spent, after point valuation, foreign transaction fees, and any open signup bonus.")
        }
    }
}

#Preview {
    EngineWorkbenchView()
        .environment(WalletStore.previewStore())
}
