import SwiftUI
import CardKit

struct SetupBenefitAdjustmentsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Card
    private let original: Card
    let onSave: (Card) -> Void
    init(card: Card, onSave: @escaping (Card) -> Void) {
        original = card; _draft = State(initialValue: card); self.onSave = onSave
    }
    var body: some View {
        NavigationStack {
            Form {
                Text("Only change terms that differ on your account. Changes will be labeled user-provided.")
                ForEach($draft.rules) { $rule in
                    Section(rule.category.displayName) {
                        TextField("Rate", value: $rule.rate, format: .number).keyboardType(.decimalPad)
                        if let cap = rule.cap {
                            Text("Cap: $\(cap.limitDollars.description) \(cap.period.displayName). You can edit caps after adding the card.").font(.caption)
                        }
                    }
                }
            }.navigationTitle("My benefits")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Apply") {
                        draft.adjustedBenefitIDs = Array(Set((draft.adjustedBenefitIDs ?? []) + draft.rules.filter {
                            original.rule(for: $0.category)?.rate != $0.rate
                        }.map { BenefitOrigin.rule($0.category).identifier }))
                        onSave(draft); dismiss()
                    }.disabled(draft.rules.contains { !$0.rate.isFinite || $0.rate < 0 || $0.rate > 100 }) }
                }
        }
    }
}
