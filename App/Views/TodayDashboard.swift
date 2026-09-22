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

/// The answer to "which card, for this, right now" — and the only place on
/// Home that names one card.
///
/// **The card is the answer, so the card is the biggest thing in the panel.**
/// The first version of this drew a 62pt thumbnail beside two lines of text:
/// the picture was smaller than the words describing it, and the thing you
/// are being told to pull out of your pocket was the least visible element on
/// the screen. The face is now roughly twice that, the card's name is the
/// panel's headline rather than a subtitle, and the rate sits in a badge
/// against it instead of being buried in the middle of a sentence.
///
/// The rate appears **once**. `choiceRationale` exists so the line under the
/// card can explain why it won without repeating the badge above it.
private struct TodayRecommendation: View {
    @Environment(WalletStore.self) private var wallet
    @Environment(OrganizationStore.self) private var organization
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var category: SpendingCategory = .dining

    var body: some View {
        let context = PurchaseContext(category: category, confidence: .categoryOnly, isTraveling: category.isTravelRelated, date: Date())
        if let recommendation = wallet.recommendation(for: context) {
            VStack(alignment: .leading, spacing: Metric.snug) {
                categoryRow
                Hairline()
                answer(recommendation)
                RecommendationReason(recommendation: recommendation, contextName: category.displayName, includesRate: false)
            }
            .padding(Metric.regular)
            .interfacePanel(tinted: true)
        }
    }

    private var categoryRow: some View {
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
    }

    /// The card, the name, the rate. Side by side, until the type size means
    /// the name would be cut in half — then the card goes above it, which is
    /// what the hero on the map sheet does for the same reason.
    @ViewBuilder
    private func answer(_ recommendation: Recommendation) -> some View {
        let card = recommendation.best.card
        let face = CardFaceView(card: card, isRecommended: true, photo: wallet.photo(for: card), use: .appDisplay)
            .frame(width: faceWidth, height: faceWidth / 1.586)
            .shadow(color: Color.cardWiseNavy.opacity(0.22), radius: 8, y: 4)

        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Metric.snug) {
                face
                identity(card: card, recommendation: recommendation)
            }
        } else {
            HStack(alignment: .center, spacing: Metric.regular) {
                face
                identity(card: card, recommendation: recommendation)
                Spacer(minLength: 0)
            }
        }
    }

    private func identity(card: Card, recommendation: Recommendation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Best for \(category.displayName.lowercased())")
                .font(.caption.weight(.semibold))
                .foregroundStyle(InterfacePalette.blue)
            Text(organization.name(for: card))
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(InterfacePalette.ink)
            RateBadge(text: recommendation.best.reason)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    private var faceWidth: CGFloat { typeSize.isAccessibilitySize ? 168 : 132 }
}

/// What the winning card pays here — "4x dining", in the card's own units.
///
/// A badge rather than a sentence because it is the one fact worth reading
/// from arm's length, and because a percent and a multiplier are never
/// compared: it states one card's rate and makes no claim about the others.
/// `surface` on the tinted panel, so it lifts in both appearances — the
/// light/dark pair is the established blue-on-surface one.
private struct RateBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(InterfacePalette.blue)
            .padding(.horizontal, Metric.snug)
            .padding(.vertical, 6)
            .background(InterfacePalette.surface, in: Capsule())
            .fixedSize(horizontal: false, vertical: true)
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
            .keyboardDoneButton()
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
