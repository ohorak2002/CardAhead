import SwiftUI
import CardKit

struct TodayDashboard: View {
    @Environment(WalletStore.self) private var wallet
    @Environment(OrganizationStore.self) private var organization
    @Environment(NearbyPlacesStore.self) private var nearby
    var goToMap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Metric.regular) {
            HStack(alignment: .firstTextBaseline) {
                Text("Today").font(.title2.bold()).foregroundStyle(InterfacePalette.ink)
                Spacer()
                Text(Date(), format: .dateTime.month(.abbreviated).day())
                    .font(.subheadline).foregroundStyle(Color.secondary)
            }
            TodayRecommendation()
            nearbyRow
            if let deadline = EverydayInsights.deadlines(in: wallet.cards).first,
               let card = wallet.card(withID: deadline.cardID) {
                NavigationLink { BenefitTimelineView() } label: {
                    DeadlineRow(item: deadline, cardName: organization.name(for: card))
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink { BenefitTimelineView() } label: {
                    Label("View your benefit timeline", systemImage: "calendar")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: Metric.minimumTarget, alignment: .leading)
                        .padding(Metric.snug).interfacePanel()
                }.buttonStyle(.plain).foregroundStyle(InterfacePalette.blue)
            }
            MonthlyRewardsPanel()
        }
        .padding(.horizontal, Metric.margin)
    }

    private var nearbyRow: some View {
        let opportunities = nearby.results.filter(\.isOpportunity)
        let nearest = opportunities.min { $0.distanceMeters < $1.distanceMeters }
        return Button(action: goToMap) {
            HStack(alignment: .top, spacing: Metric.snug) {
                CategoryIcon(symbolName: "mappin.and.ellipse", tint: InterfacePalette.blue)
                VStack(alignment: .leading, spacing: Metric.tight) {
                    Text(opportunities.isEmpty ? "Explore nearby" : "\(opportunities.count) nearby \(opportunities.count == 1 ? "opportunity" : "opportunities")")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary)
                    if let nearest {
                        Text("\(nearest.place.name), \(nearest.distanceText)")
                            .font(.caption).foregroundStyle(Color.secondary)
                        if let rec = nearest.recommendation {
                            Text(rec.choiceExplanation).font(.caption).foregroundStyle(Color.secondary)
                        }
                    } else {
                        Text(nearby.failure != nil ? "The last lookup did not finish. Open the map to retry." : "Open the map to find places and check which card to use.")
                            .font(.caption).foregroundStyle(Color.secondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(InterfacePalette.blue)
            }
            .padding(Metric.regular).interfacePanel()
        }
        .buttonStyle(.plain)
    }

}

private struct TodayRecommendation: View {
    @Environment(WalletStore.self) private var wallet
    @Environment(OrganizationStore.self) private var organization
    @State private var category: SpendingCategory = .dining

    var body: some View {
        let context = PurchaseContext(category: category, confidence: .categoryOnly, isTraveling: category.isTravelRelated, date: Date())
        if let recommendation = wallet.recommendation(for: context) {
            VStack(alignment: .leading, spacing: Metric.snug) {
                HStack {
                    Text("Buying").font(.subheadline).foregroundStyle(Color.secondary)
                    Spacer()
                    Picker("Buying", selection: $category) {
                        ForEach(SpendingCategory.allCases, id: \.self) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(minHeight: Metric.minimumTarget)
                }
                HStack(alignment: .top, spacing: Metric.snug) {
                    CardThumbnail(card: recommendation.best.card, photo: wallet.photo(for: recommendation.best.card))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Your best card for \(category.displayName.lowercased())")
                            .font(.caption.weight(.medium)).foregroundStyle(InterfacePalette.blue)
                        Text(organization.name(for: recommendation.best.card)).font(.headline)
                            .foregroundStyle(InterfacePalette.ink)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                RecommendationReason(recommendation: recommendation, contextName: category.displayName)
            }
            .padding(Metric.regular)
            .interfacePanel(tinted: true)
        }
    }
}

struct MonthlyRewardsPanel: View {
    @Environment(ImpactStore.self) private var impact
    @Environment(OrganizationStore.self) private var organization
    @State private var showingGoal = false

    var body: some View {
        let summary = EverydayInsights.monthlyImpact(impact.ledger)
        let dollars = summary.estimatedIncrementalValueCents / 100
        let goal = organization.preferences.monthlyGoalDollars
        return VStack(alignment: .leading, spacing: Metric.snug) {
            Text("This month's rewards").font(.headline)
            if !impact.isRecording {
                Text("Impact recording is off. You can turn it on in Your impact.")
                    .font(.subheadline).foregroundStyle(Color.secondary)
            } else if summary.priced == 0 {
                Text("Your first estimate starts here")
                    .font(.title3.weight(.semibold)).foregroundStyle(InterfacePalette.blue)
                Text("After you use a recommendation, enter the purchase amount in its follow-up. Estimated extra rewards will appear here.")
                    .font(.caption).foregroundStyle(Color.secondary)
            } else {
                Text(dollars, format: .currency(code: "USD"))
                    .font(.system(.largeTitle, design: .rounded).bold()).monospacedDigit()
                    .foregroundStyle(InterfacePalette.blue)
                Text("Estimated extra rewards from \(summary.priced) \(summary.priced == 1 ? "purchase" : "purchases") priced this month.")
                    .font(.caption).foregroundStyle(Color.secondary)
            }
            if impact.isRecording, let goal, goal > 0 {
                ProgressView(value: min(1, max(0, dollars / goal.doubleValue)))
                    .tint(InterfacePalette.blue)
                    .accessibilityLabel("Monthly rewards goal")
                    .accessibilityValue("\(Int(min(1, max(0, dollars / goal.doubleValue)) * 100)) percent")
                Text("Your goal: \(CardWiseFormat.money(goal)) in estimated extra rewards")
                    .font(.caption).foregroundStyle(Color.secondary)
            }
            ViewThatFits(in: .horizontal) {
                HStack { impactLink; Spacer(); goalButton }
                VStack(alignment: .leading) { impactLink; goalButton }
            }
        }
        .padding(Metric.regular).interfacePanel()
        .sheet(isPresented: $showingGoal) { MonthlyGoalView() }
    }

    private var impactLink: some View {
        NavigationLink("View your impact") { ImpactView() }
            .font(.subheadline.weight(.semibold)).frame(minHeight: Metric.minimumTarget)
    }

    private var goalButton: some View {
        Button(organization.preferences.monthlyGoalDollars == nil ? "Set a goal" : "Edit goal") { showingGoal = true }
            .font(.subheadline).frame(minHeight: Metric.minimumTarget)
    }
}

struct MonthlyGoalView: View {
    @Environment(OrganizationStore.self) private var organization
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""

    private var value: Decimal? { WalletOrganization.goal(from: amount) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Estimated extra rewards per month") {
                    TextField("Amount in USD", text: $amount)
                        .keyboardType(.decimalPad)
                        .accessibilityLabel("Monthly goal in US dollars")
                    Text("Choose a personal target for rewards above your next best card. This is not a spending target or a promise of earnings.")
                        .font(.caption).foregroundStyle(Color.secondary)
                }
                if let failure = organization.failure { Text(failure).foregroundStyle(Color.cardWiseError) }
                if organization.preferences.monthlyGoalDollars != nil {
                    Button("Remove goal") {
                        if organization.update({ $0.monthlyGoalDollars = nil }) { dismiss() }
                    }
                }
            }
            .navigationTitle("Monthly goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let value, organization.update({ $0.monthlyGoalDollars = value }) { dismiss() }
                    }.disabled(value == nil)
                }
            }
            .onAppear { amount = organization.preferences.monthlyGoalDollars.map { NSDecimalNumber(decimal: $0).stringValue } ?? "" }
        }
    }
}
