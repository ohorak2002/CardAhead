import Foundation

/// Picks the card to pay with. Pure, synchronous, and free of Core Location,
/// so it can be exercised entirely from unit tests.
///
/// The ranking the product spec asks for is expressed as a single score in
/// cents per dollar, so the pieces are comparable instead of being an
/// arbitrary pile of tiebreak rules:
///
/// 1. The best rate that actually applies, converted through the user's own
///    point valuation. A bonus rate whose cap is used up does not apply, and a
///    rotating bonus the user never activated does not apply either.
/// 2. Abroad, a foreign transaction fee is subtracted. It is real money lost.
/// 3. An open welcome bonus is divided across the spend still required, which
///    turns "weight this heavily" into an actual number rather than a fudge factor.
/// 4. Only genuine ties fall through to pinned, then cap health, then travel
///    perks, then annual fee, then name — so the order is always stable.
public struct RecommendationEngine: Sendable {
    /// A welcome bonus with a dollar of spend left would otherwise score in the
    /// thousands. This ceiling keeps a nearly-finished bonus from swamping everything.
    public var maxWelcomeBonusBoostCentsPerDollar: Double
    /// Two scores closer than this count as tied.
    public var tieTolerance: Double
    /// Below this gap, in cents per dollar, the best card is not interrupting
    /// anyone for — see `reminder(for:cards:asOf:)` in `ArrivalReminder.swift`.
    /// Far looser than `tieTolerance`: that one catches genuine floating-point
    /// ties for sorting, this one catches a real but trivial edge that is not
    /// worth a lock-screen notification. Half a cent is a nickel on a $10
    /// coffee and real money on a $500 purchase — the same fixed gap reads
    /// very differently depending on what is actually being bought, but the
    /// app has no idea how much this purchase will be, only which category it
    /// is in, so a flat per-dollar threshold is the honest thing to check.
    public var minimumArrivalEdgeCentsPerDollar: Double

    public init(
        maxWelcomeBonusBoostCentsPerDollar: Double = 25.0,
        tieTolerance: Double = 0.001,
        minimumArrivalEdgeCentsPerDollar: Double = 0.5
    ) {
        self.maxWelcomeBonusBoostCentsPerDollar = maxWelcomeBonusBoostCentsPerDollar
        self.tieTolerance = tieTolerance
        self.minimumArrivalEdgeCentsPerDollar = minimumArrivalEdgeCentsPerDollar
    }

    // MARK: - Scoring

    public func score(
        _ card: Card,
        in context: PurchaseContext,
        forcingRotatingActivation: Bool = false
    ) -> CardScore {
        let quarter = Quarter.containing(context.date)
        var caveats: [String] = []

        var appliedRate = card.baseRate
        var source: RateSource = .base
        var isCapExhausted = false
        var isRotatingMatch = false
        var needsActivation = false

        // A permanent bonus rule, if the card has one for this category.
        if context.category != .base, let rule = card.rule(for: context.category) {
            if let cap = rule.cap, cap.isExhausted {
                isCapExhausted = true
                let limit = Self.dollars(cap.limitDollars)
                let fallback = card.currency.formatted(rate: card.baseRate)
                caveats.append("\(context.category.displayName) cap of \(limit) \(cap.period.displayName) is used up. Earning \(fallback) here.")
            } else if rule.rate > appliedRate {
                appliedRate = rule.rate
                source = .permanent(rule.category)
            }
        }

        // This quarter's rotating bonus, if it covers the category — and a word
        // about it when nobody has published this quarter yet, because leaving
        // a 5% bonus silently out of a ranking is the one omission the user
        // would want to know about.
        if let program = card.rotatingProgram {
            switch program.status(for: quarter) {
            case .bonus(let rotatingQuarter) where rotatingQuarter.categories.contains(context.category):
                isRotatingMatch = true
                let activated = rotatingQuarter.isActivated || forcingRotatingActivation
                if !rotatingQuarter.isActivated {
                    needsActivation = true
                }
                if !activated {
                    let rate = card.currency.formatted(rate: program.rate)
                    caveats.append("The \(rate) bonus for this quarter has not been activated.")
                } else if let cap = program.cap, cap.isExhausted {
                    isCapExhausted = true
                    let limit = Self.dollars(cap.limitDollars)
                    caveats.append("Rotating bonus cap of \(limit) \(cap.period.displayName) is used up.")
                } else if program.rate > appliedRate {
                    appliedRate = program.rate
                    source = .rotating(rotatingQuarter.quarter)
                }

            case .unannounced:
                let rate = card.currency.formatted(rate: program.rate)
                caveats.append("Nobody has said what \(card.displayName) pays \(rate) on this quarter, so this leaves it out.")

            default:
                break
            }
        }

        var effective = appliedRate * card.currency.centsPerUnit

        if context.isAbroad && card.foreignTransactionFeePercent > 0 {
            effective -= card.foreignTransactionFeePercent
            let fee = Self.trim(card.foreignTransactionFeePercent)
            caveats.append("\(fee)% foreign transaction fee applies abroad.")
        }

        let boost = welcomeBonusBoost(for: card, asOf: context.date)
        if boost > 0, let bonus = card.welcomeBonus {
            let left = Self.dollars(bonus.remainingSpendDollars)
            let days = bonus.daysRemaining(asOf: context.date)
            caveats.append("Signup bonus: \(left) of spend left, \(days) days to go.")
        }

        caveats.append(contentsOf: card.notes(for: context.category).map(\.text))

        return CardScore(
            card: card,
            appliedRate: appliedRate,
            source: source,
            effectiveCentsPerDollar: effective,
            welcomeBonusBoostCentsPerDollar: boost,
            total: effective + boost,
            isRotatingMatch: isRotatingMatch,
            needsActivation: needsActivation,
            isCapExhausted: isCapExhausted,
            reason: reason(rate: appliedRate, source: source, card: card),
            caveats: caveats
        )
    }

    /// An open signup bonus, spread across the spend still required.
    /// $600 of points with $3,000 left to spend is worth 20 cents on the dollar,
    /// which correctly outranks any 5% category.
    public func welcomeBonusBoost(for card: Card, asOf date: Date) -> Double {
        guard let bonus = card.welcomeBonus, bonus.isOpen(asOf: date) else { return 0 }
        let remaining = bonus.remainingSpendDollars.doubleValue
        guard remaining > 0 else { return 0 }
        let valueInCents = bonus.rewardUnits * card.currency.centsPerUnit
        return min(valueInCents / remaining, maxWelcomeBonusBoostCentsPerDollar)
    }

    // MARK: - Ranking

    public func rank(_ cards: [Card], in context: PurchaseContext) -> [CardScore] {
        let scores = cards.map { score($0, in: context) }
        return scores.sorted { isBetter($0, than: $1, in: context) }
    }

    public func recommend(from cards: [Card], in context: PurchaseContext) -> Recommendation? {
        let ranked = rank(cards, in: context)
        guard let best = ranked.first else { return nil }

        return Recommendation(
            best: best,
            alternates: Array(ranked.dropFirst()),
            headline: headline(for: best, in: context),
            detail: detail(for: best, in: context),
            activationNudge: activationNudge(beating: best, among: cards, in: context),
            travelPerkSummary: travelPerkSummary(for: best, in: context)
        )
    }

    private func isBetter(_ lhs: CardScore, than rhs: CardScore, in context: PurchaseContext) -> Bool {
        if abs(lhs.total - rhs.total) > tieTolerance { return lhs.total > rhs.total }
        if lhs.card.isPinned != rhs.card.isPinned { return lhs.card.isPinned }
        if lhs.isCapExhausted != rhs.isCapExhausted { return !lhs.isCapExhausted }
        if context.isTraveling {
            let left = lhs.travelPerks.count
            let right = rhs.travelPerks.count
            if left != right { return left > right }
        }
        if lhs.card.annualFeeDollars != rhs.card.annualFeeDollars {
            return lhs.card.annualFeeDollars < rhs.card.annualFeeDollars
        }
        return lhs.card.displayName < rhs.card.displayName
    }

    // MARK: - Copy

    private func reason(rate: Double, source: RateSource, card: Card) -> String {
        let formatted = card.currency.formatted(rate: rate)
        switch source {
        case .base:
            return "\(formatted) on everything"
        case .permanent(let category):
            return "\(formatted) \(category.displayName.lowercased())"
        case .rotating:
            return "\(formatted) rotating bonus this quarter"
        }
    }

    private func headline(for best: CardScore, in context: PurchaseContext) -> String {
        switch context.confidence {
        case .exact:
            return "Use \(best.card.displayName) here"
        case .categoryOnly:
            return "\(context.category.displayName) nearby. Use \(best.card.displayName)."
        }
    }

    private func detail(for best: CardScore, in context: PurchaseContext) -> String {
        if context.confidence == .exact, let merchant = context.merchantName, !merchant.isEmpty {
            return "\(best.reason) at \(merchant)"
        }
        return best.reason
    }

    /// If a rotating bonus would have won but sits unactivated, say so. This is
    /// the case where the user is about to leave real money on the table.
    private func activationNudge(
        beating best: CardScore,
        among cards: [Card],
        in context: PurchaseContext
    ) -> String? {
        for card in cards where card.rotatingProgram != nil {
            let current = score(card, in: context)
            guard current.needsActivation else { continue }
            let activated = score(card, in: context, forcingRotatingActivation: true)
            if activated.total > best.total + tieTolerance {
                let rate = card.currency.formatted(rate: activated.appliedRate)
                return "Activate the quarterly bonus on \(card.displayName). It would pay \(rate) here."
            }
        }
        return nil
    }

    private func travelPerkSummary(for best: CardScore, in context: PurchaseContext) -> String? {
        guard context.isTraveling else { return nil }
        let perks = best.travelPerks.prefix(2).map(\.displayName)
        guard !perks.isEmpty else { return nil }
        return perks.joined(separator: " · ")
    }

    // MARK: - Formatting helpers

    static func dollars(_ amount: Money) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "$\(amount)"
    }

    static func trim(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}
