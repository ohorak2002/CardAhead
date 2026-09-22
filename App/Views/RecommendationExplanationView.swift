import SwiftUI
import CardKit

/// A contextual explanation stays with the recommendation it explains.
struct RecommendationExplanationView: View {
    let recommendation: Recommendation
    var contextName: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: Metric.snug) {
                        Text(recommendation.best.card.displayName)
                            .font(.title2.bold())
                            .foregroundStyle(InterfacePalette.ink)
                        Text(recommendation.choiceExplanation)
                            .font(.body)
                        Text(contextName).font(.subheadline).foregroundStyle(Color.secondary)
                    }
                    .padding(.vertical, Metric.tight)
                }
                Section("How your cards compare") {
                    ForEach([recommendation.best] + recommendation.alternates) { score in
                        VStack(alignment: .leading, spacing: Metric.tight) {
                            Label(score.card.displayName, systemImage: score.id == recommendation.best.id ? "checkmark.circle.fill" : "creditcard")
                                .font(.headline)
                                .foregroundStyle(score.id == recommendation.best.id ? InterfacePalette.blue : Color.primary)
                            Text(score.reason).font(.subheadline)
                            Text(String(format: "%.2f¢ estimated value per $1", score.effectiveCentsPerDollar))
                                .font(.caption).monospacedDigit().foregroundStyle(Color.secondary)
                            if score.welcomeBonusBoostCentsPerDollar > 0 {
                                Text("An open signup bonus also influences this ranking.")
                                    .font(.caption).foregroundStyle(Color.secondary)
                            }
                        }
                        .padding(.vertical, Metric.tight)
                    }
                }
                if let nudge = recommendation.activationNudge {
                    Section("Worth doing") { Text(nudge.sentence) }
                }
                if !recommendation.caveats.isEmpty {
                    Section("Before you pay") {
                        ForEach(recommendation.caveats, id: \.self) { Text($0) }
                    }
                }
                Section {
                    Text("Point values use your settings. Merchant coding and bank terms determine the rewards you actually receive. Annual fees only break an otherwise equal ranking; untracked credits are not valued.")
                        .font(.footnote).foregroundStyle(Color.secondary)
                }
            }
            .navigationTitle("Why this card?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

struct RecommendationReason: View {
    let recommendation: Recommendation
    let contextName: String
    /// False where the screen already shows the rate itself. Today's panel
    /// draws it as a badge beside the card, and the full explanation would
    /// print it again one line below.
    var includesRate = true
    @State private var isExplaining = false

    var body: some View {
        VStack(alignment: .leading, spacing: Metric.tight) {
            Text(includesRate ? recommendation.choiceExplanation : recommendation.choiceRationale)
                .font(.footnote)
                .foregroundStyle(Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button { isExplaining = true } label: {
                Label("Why this card?", systemImage: "info.circle")
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: Metric.minimumTarget)
            }
            .buttonStyle(.plain)
            .foregroundStyle(InterfacePalette.blue)
            .accessibilityIdentifier("recommendation.why")
        }
        .sheet(isPresented: $isExplaining) {
            RecommendationExplanationView(recommendation: recommendation, contextName: contextName)
        }
    }
}
