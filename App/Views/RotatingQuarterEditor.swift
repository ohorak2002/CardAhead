import SwiftUI
import CardKit

/// Asks the user what this quarter's rotating bonus is.
///
/// This is the answer to a problem with no clean technical fix. Chase and
/// Discover announce their 5% categories a quarter at a time — Chase about a
/// fortnight before it starts — so nothing shipped inside an app can know them,
/// and an app with no account and no server has nowhere to fetch them from.
/// The alternatives were all worse: guessing produces confident reminders for a
/// bonus that does not exist, and staying silent loses the user 5% for three
/// months without telling them why.
///
/// The user already knows. The issuer emailed them. This takes the ten seconds
/// once a quarter to write it down, and it is the only source that cannot go
/// stale without somebody noticing.
struct RotatingQuarterEditor: View {

    let card: Card
    let quarter: Quarter

    @Environment(WalletStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var chosen: Set<SpendingCategory> = []
    @State private var isActivated = false

    private var program: RotatingProgram? { card.rotatingProgram }

    /// Everything except the catch-all. A quarter's real wording often includes
    /// things with no shop behind them — utility bills, charity, one retailer's
    /// website — and those simply have no row here, which is why the note below
    /// says so rather than pretending the list is complete.
    private var choices: [SpendingCategory] {
        SpendingCategory.allCases
            .filter { $0 != .base }
            .sorted { $0.displayName < $1.displayName }
    }

    var body: some View {
        NavigationStack {
            List {
                explanation
                categoryPicker
                activationRow
            }
            .navigationTitle("\(quarter.rawValue) on \(card.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(chosen.isEmpty)
                }
            }
            .onAppear(perform: loadExisting)
        }
    }

    private var explanation: some View {
        Section {
            Text("\(card.issuer) announces these a quarter at a time, so nothing that shipped with this app could know them. You will have had the email.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let source = program?.sourceURL, let url = URL(string: source) {
                Link(destination: url) {
                    Label("Look it up at \(card.issuer)", systemImage: "arrow.up.right.square")
                }
            }
        }
    }

    private var categoryPicker: some View {
        Section {
            ForEach(choices, id: \.self) { category in
                Button {
                    if chosen.contains(category) {
                        chosen.remove(category)
                    } else {
                        chosen.insert(category)
                    }
                } label: {
                    HStack {
                        Text(category.displayName)
                            .foregroundStyle(.primary)
                        Spacer(minLength: 8)
                        if chosen.contains(category) {
                            Image(systemName: "checkmark")
                                .font(.footnote.weight(.semibold))
                        }
                    }
                }
            }
        } header: {
            Text("What earns \(rateText) this quarter").textCase(nil)
        } footer: {
            Text("Only places you walk into are listed. A quarter often includes things like utility bills or a single retailer's website, and this app has no way to notice those, so leave them out.")
        }
    }

    private var activationRow: some View {
        Section {
            Toggle("I have activated it with \(card.issuer)", isOn: $isActivated)
        } footer: {
            Text("Until it is switched on with the issuer, the bonus pays nothing, whatever you buy. If you are not sure, leave this off and the app will keep reminding you.")
        }
    }

    private var rateText: String {
        guard let program else { return "the bonus" }
        return card.currency.formatted(rate: program.rate)
    }

    /// Re-opening the sheet shows what was entered last time rather than a
    /// blank form, so correcting one category does not mean retyping them all.
    private func loadExisting() {
        guard let existing = program?.quarter(quarter) else { return }
        chosen = Set(existing.categories)
        isActivated = existing.isActivated
    }

    private func save() {
        store.setRotatingCategories(
            choices.filter { chosen.contains($0) },
            activated: isActivated,
            cardID: card.id,
            quarter: quarter
        )
        dismiss()
    }
}

#Preview {
    RotatingQuarterEditor(
        card: CardCatalog.chaseFreedomFlex,
        quarter: Quarter(year: 2026, index: 4)
    )
    .environment(WalletStore.previewStore())
}
