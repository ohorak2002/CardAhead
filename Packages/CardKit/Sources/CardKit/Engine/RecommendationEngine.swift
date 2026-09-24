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
        var appliedCap: EarnCap?

        // A permanent bonus rule, if the card has one for this category.
        if context.category != .base, let rule = card.rule(for: context.category) {
            let restriction = CardCatalog.entry(for: card)?.card.rule(for: context.category)
            let merchantAllowed = (rule.merchantNames ?? restriction?.merchantNames).map { names in
                context.confidence == .exact && context.merchantName.map { merchant in
                    names.contains { PersonalOffer.normalized($0) == PersonalOffer.normalized(merchant) }
                } == true
            } ?? true
            let confirmed = (rule.requiresConfirmation ?? restriction?.requiresConfirmation) != true || context.confirmedBenefitIDs.contains(BenefitOrigin.rule(rule.category).identifier)
            let domesticOnly = (card.catalogProductID == "amex-blue-cash-preferred" && [.groceries, .gas, .streaming].contains(context.category))
                || (card.catalogProductID == "amex-gold" && context.category == .groceries)
            if !merchantAllowed || !confirmed || (domesticOnly && context.isAbroad) {
                caveats.append("Conditional benefit: " + (rule.note ?? "Confirm issuer eligibility."))
            } else
            if let cap = rule.cap, cap.isExhausted {
                isCapExhausted = true
                let limit = Self.dollars(cap.limitDollars)
                let fallback = card.currency.formatted(rate: card.baseRate)
                caveats.append("\(context.category.displayName) cap of \(limit) \(cap.period.displayName) is used up. Earning \(fallback) here.")
            } else if rule.rate > appliedRate {
                appliedRate = rule.rate
                appliedCap = rule.cap
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
                    appliedCap = program.cap
                    source = .rotating(rotatingQuarter.quarter)
                }

            case .unannounced:
                let rate = card.currency.formatted(rate: program.rate)
                caveats.append("CardAhead has not verified what \(card.displayName) pays \(rate) on this quarter, so this leaves it out.")

            default:
                break
            }
        }

        var effective = appliedRate * card.currency.centsPerUnit
        if let cap = appliedCap {
            if !cap.usageIsCurrent(asOf: context.date) {
                caveats.append("Cap usage is unknown for this period. Enter current spend before relying on the bonus.")
            }
            if let amount = context.purchaseDollars, amount > 0 {
                let eligible = min(amount, cap.remainingDollars)
                effective = ((eligible * Decimal(appliedRate) + (amount - eligible) * Decimal(card.baseRate))
                    * Decimal(card.currency.centsPerUnit) / amount).doubleValue
            }
        }
        // Costco gas shares the existing gas cap. Exact aliases only.
        if card.catalogProductID == "citi-costco-anywhere-visa", context.category == .gas,
           context.confidence == .exact, let name = context.merchantName,
           ["costco", "costco gas", "costco gasoline", "costco wholesale"].contains(PersonalOffer.normalized(name)),
           !isCapExhausted {
            appliedRate = 5
            let amount = context.purchaseDollars
            if let amount, amount > 0, let cap = appliedCap {
                let eligible = min(amount, cap.remainingDollars)
                effective = ((eligible * 5 + (amount - eligible) * Decimal(card.baseRate)) / amount).doubleValue
            } else { effective = 5 }
        }

        let evaluations = card.effectiveOffers.compactMap {
            OfferEvaluator.evaluate($0, in: context, centsPerPoint: card.currency.centsPerUnit)
        }
        caveats.append(contentsOf: evaluations.map(\.explanation))
        // Multiple offers may conflict; choose the best single eligible offer.
        // No offer-to-offer stacking is inferred.
        let standardEffective = effective
        var offerApplied = false
        for evaluation in evaluations {
            guard let rate = evaluation.centsPerDollar,
                  let offer = card.effectiveOffers.first(where: { $0.id == evaluation.offerID }) else { continue }
            let standard = standardEffective
            let candidate = offer.stacking == .addsToStandard ? standard + rate : rate
            if candidate > effective { effective = candidate; offerApplied = true }
        }

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
        if context.merchantName != nil {
            caveats.append("Map categories are estimates, not issuer merchant codes. Actual rewards depend on how the purchase is processed.")
        }

        var result = CardScore(
            card: card,
            appliedRate: appliedRate,
            source: source,
            effectiveCentsPerDollar: effective,
            welcomeBonusBoostCentsPerDollar: boost,
            total: effective + boost,
            isRotatingMatch: isRotatingMatch,
            needsActivation: needsActivation,
            isCapExhausted: isCapExhausted,
            reason: offerApplied ? "Estimated reward includes your eligible personal offer" : reason(rate: appliedRate, source: source, card: card),
            caveats: caveats
        )
        result.capRemainingDollars = appliedCap?.remainingDollars
        result.baseCentsPerDollar = card.baseRate * card.currency.centsPerUnit - (context.isAbroad ? card.foreignTransactionFeePercent : 0)
        result.pricedPurchaseDollars = context.purchaseDollars
        result.includesPersonalOffer = offerApplied
        return result
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

    /// The title: an emoji, and *where*. Nothing else.
    ///
    /// **It used to be where and which card and a full stop** — "Transit
    /// nearby. Use Capital One Savor." — and iOS showed "Transit nearby. Use
    /// Capital One S…", so the card it named was the part that got cut. A
    /// notification title has room for about one short phrase. Spending it on
    /// the place and leaving the card to the body means both survive, because
    /// the body gets two full lines and the title gets a third of one.
    ///
    /// The place is the right thing to put in the small space for a second
    /// reason: it is what makes the reminder *make sense*. "Use Capital One
    /// Savor" arriving out of nowhere is a demand; "Restaurant nearby" is an
    /// observation the reader can check against the building in front of them.
    ///
    /// The emoji goes **after** the name — "Chick-fil-A 🍽️" — so the name is
    /// the first thing read, and the emoji decorates it rather than leading.
    private func headline(for best: CardScore, in context: PurchaseContext) -> String {
        let emoji = context.category.emoji
        if namesThePlace(context), let merchant = context.merchantName {
            return "\(merchant) \(emoji)"
        }
        return "\(context.category.placePhrase) nearby \(emoji)"
    }

    /// The body: one instruction, in the shape somebody would say it out
    /// loud. "Use Amex Gold here for 4x at restaurants!"
    ///
    /// The card name has to be here rather than the title because it is the
    /// thing being asked for, and a truncated card name is a reminder that
    /// failed. The merchant is deliberately *not* repeated — the title just
    /// said it, so "here" stands in for it. "Here" only when the title named
    /// one place: "Restaurant nearby" has not said where "here" is.
    private func detail(for best: CardScore, in context: PurchaseContext) -> String {
        let card = best.card.displayName
        let here = namesThePlace(context) ? " here" : ""
        if best.includesPersonalOffer { return "Use \(card)\(here) to get your personal offer!" }
        return "Use \(card)\(here) for \(rewardPhrase(for: best, in: context))!"
    }

    private func namesThePlace(_ context: PurchaseContext) -> Bool {
        context.confidence == .exact && !(context.merchantName ?? "").isEmpty
    }

    /// The tail of that sentence: the rate, and what it is a rate *on*.
    ///
    /// Not `best.reason`, which is written to stand alone in a list of cards
    /// ("4x dining") and reads like a fragment once "Use Amex Gold for" is in
    /// front of it. `benefitPhrase` is the form that was already written to
    /// be the tail of a sentence.
    ///
    /// A percent is cash back, so it says "back" — "6% back at supermarkets".
    /// A multiplier is points, where "4x back" is not how anyone talks.
    private func rewardPhrase(for best: CardScore, in context: PurchaseContext) -> String {
        var rate = best.card.currency.formatted(rate: best.appliedRate)
        if best.card.currency.style == .percent { rate += " back" }
        switch best.source {
        case .base:
            return "\(rate) on everything"
        case .permanent(let category):
            return "\(rate) \(category.benefitPhrase)"
        case .rotating:
            return "\(rate) this quarter"
        }
    }

    /// If a rotating bonus would have won but sits unactivated, say so. This is
    /// the case where the user is about to leave real money on the table.
    private func activationNudge(
        beating best: CardScore,
        among cards: [Card],
        in context: PurchaseContext
    ) -> ActivationNudge? {
        for card in cards where card.rotatingProgram != nil {
            let current = score(card, in: context)
            guard current.needsActivation else { continue }
            let activated = score(card, in: context, forcingRotatingActivation: true)
            if activated.total > best.total + tieTolerance {
                return ActivationNudge(
                    cardName: card.displayName,
                    rateText: card.currency.formatted(rate: activated.appliedRate)
                )
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
