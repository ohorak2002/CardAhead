import Foundation

/// Which shelf a benefit sits on in the Benefits screen.
///
/// These are the words a person would use about their own wallet, not the
/// engine's categories. Several spending categories collapse into one group on
/// purpose: nobody thinks of "flights", "hotels" and "transit" as three
/// separate things their card is good for, they think "travel".
public enum BenefitGroup: String, Codable, CaseIterable, Sendable, Hashable {
    case dining
    case groceries
    case gas
    case travel
    case entertainment
    case drugstores
    case shopping
    case everydaySpending
    case cardPerks
    case creditsAndBonuses

    public var displayName: String {
        switch self {
        case .dining: return "Dining"
        case .groceries: return "Groceries"
        case .gas: return "Gas & EV"
        case .travel: return "Travel"
        case .entertainment: return "Entertainment"
        case .drugstores: return "Drugstores"
        case .shopping: return "Shopping"
        case .everydaySpending: return "Everything else"
        case .cardPerks: return "Card perks"
        case .creditsAndBonuses: return "Credits & bonuses"
        }
    }

    /// Declaration order is display order: the things a card pays extra on
    /// first, the base rate after them, and the non-earning benefits last.
    public var sortOrder: Int {
        Self.allCases.firstIndex(of: self) ?? Self.allCases.count
    }

    public static func containing(_ category: SpendingCategory) -> BenefitGroup {
        switch category {
        case .dining: return .dining
        case .groceries, .warehouseClub: return .groceries
        case .gas: return .gas
        case .travel, .travelPortal, .flights, .hotels, .transit, .rideshare: return .travel
        case .streaming, .entertainment: return .entertainment
        case .drugstores: return .drugstores
        case .onlineShopping, .departmentStore, .homeImprovement: return .shopping
        case .base: return .everydaySpending
        }
    }
}

/// What sort of benefit it is. A rate you earn, a thing you get, or money back.
public enum BenefitKind: String, Codable, CaseIterable, Sendable, Hashable {
    case rewardRate
    /// The quarterly 5% that changes categories four times a year.
    case rotatingRate
    case perk
    case credit
    case bonus
    case insurance
    case access
}

/// Whether this came out of the audited catalog or off the top of somebody's
/// head. The screen shows a source and a date for one and not the other.
public enum BenefitSource: String, Codable, Sendable, Hashable {
    case catalog
    case user
}

/// Which structure on the card this benefit was read out of.
///
/// This is the whole reason the Benefits screen can be a view of the card
/// rather than a second copy of it: when somebody removes a benefit, the origin
/// says exactly what to change on the card itself. There is no separate list to
/// keep in step, and no second place for the ranking engine to disagree with.
public enum BenefitOrigin: Codable, Hashable, Sendable {
    case rule(SpendingCategory)
    case rotating
    case perk(Perk)
    case welcomeBonus

    /// Stable across a redraw, so SwiftUI keeps a row where it was.
    public var identifier: String {
        switch self {
        case .rule(let category): return "rule.\(category.rawValue)"
        case .rotating: return "rotating"
        case .perk(let perk): return "perk.\(perk.rawValue)"
        case .welcomeBonus: return "welcomeBonus"
        }
    }
}

/// One thing a card is good for, said in words.
///
/// **This is a presentation layer, not a second engine.** Every benefit here is
/// derived from the `Card` the ranking engine already reads — the rules, the
/// rotating programme, the perks, an open signup bonus — and nothing is stored
/// twice. `RecommendationEngine` remains the only thing that decides which card
/// wins; see the note on `CardBenefit.benefits(for:asOf:)`.
public struct CardBenefit: Identifiable, Codable, Hashable, Sendable {
    public var id: String { origin.identifier }

    public var origin: BenefitOrigin
    public var group: BenefitGroup
    public var kind: BenefitKind
    /// Plain language, and the only line most people will read: "4x at
    /// restaurants", never "CategoryRule(category: .dining, rate: 4)".
    public var title: String
    /// The caveat, when there is one worth carrying: "U.S. supermarkets only."
    public var detail: String?
    public var rate: Double?
    public var cap: EarnCap?
    public var source: BenefitSource
    /// The day somebody last read this off the issuer's own page. Nil for a
    /// card described by hand, because then nobody did.
    public var verifiedOn: Date?
    public var sourceURL: String?
    public var expiresOn: Date?
    /// False when the benefit exists but is not paying right now: a cap used
    /// up, a quarter not switched on, a signup bonus already met.
    public var isActive: Bool
    public var relatedSpendingCategory: SpendingCategory?
    /// False for benefits nothing in the app can switch off. The base rate is
    /// what every other rule falls back to, and a rotating programme is the
    /// issuer's, not ours.
    public var isRemovable: Bool

    public init(
        origin: BenefitOrigin,
        group: BenefitGroup,
        kind: BenefitKind,
        title: String,
        detail: String? = nil,
        rate: Double? = nil,
        cap: EarnCap? = nil,
        source: BenefitSource = .user,
        verifiedOn: Date? = nil,
        expiresOn: Date? = nil,
        isActive: Bool = true,
        relatedSpendingCategory: SpendingCategory? = nil,
        isRemovable: Bool = true
    ) {
        self.origin = origin
        self.group = group
        self.kind = kind
        self.title = title
        self.detail = detail
        self.rate = rate
        self.cap = cap
        self.source = source
        self.verifiedOn = verifiedOn
        self.expiresOn = expiresOn
        self.isActive = isActive
        self.relatedSpendingCategory = relatedSpendingCategory
        self.isRemovable = isRemovable
    }
}

// MARK: - Reading a card as benefits

extension CardBenefit {

    /// Everything this card is good for, in the order a person would want to
    /// read it.
    ///
    /// Derived every time rather than stored. A stored copy would be a second
    /// description of the same card, free to drift from the one the ranking
    /// engine reads — and the two disagreeing is precisely the bug that would
    /// be impossible to find from a screenshot.
    public static func benefits(for card: Card, asOf date: Date = Date()) -> [CardBenefit] {
        let entry = CardCatalog.entry(for: card)
        let source: BenefitSource = entry == nil ? .user : .catalog
        let verifiedOn = entry?.checkedOn

        var found: [CardBenefit] = card.rules.map { rule in
            CardBenefit(
                origin: .rule(rule.category),
                group: BenefitGroup.containing(rule.category),
                kind: .rewardRate,
                title: "\(card.currency.formatted(rate: rule.rate)) \(rule.category.benefitPhrase)",
                detail: rule.note,
                rate: rule.rate,
                cap: rule.cap,
                source: source,
                verifiedOn: verifiedOn,
                isActive: !(rule.cap?.isExhausted ?? false),
                relatedSpendingCategory: rule.category,
                isRemovable: rule.category != .base
            )
        }

        if let program = card.rotatingProgram {
            found.append(rotatingBenefit(program, on: card, source: source, verifiedOn: verifiedOn, asOf: date))
        }

        found.append(contentsOf: card.perks.map { perk in
            CardBenefit(
                origin: .perk(perk),
                group: perk.benefitGroup,
                kind: perk.benefitKind,
                title: perk.displayName,
                source: source,
                verifiedOn: verifiedOn
            )
        })

        if let bonus = card.welcomeBonus, !bonus.isExpired(asOf: date) {
            found.append(welcomeBenefit(bonus, on: card, source: source, verifiedOn: verifiedOn, asOf: date))
        }

        for index in found.indices {
            let origin = found[index].origin
            if card.isUserAdjusted(origin) {
                found[index].source = .user
                found[index].verifiedOn = nil
            } else {
                found[index].verifiedOn = entry?.verifiedDate(for: origin)
                found[index].sourceURL = entry?.termsURL
            }
        }
        return found.sorted { lhs, rhs in
            if lhs.group != rhs.group { return lhs.group.sortOrder < rhs.group.sortOrder }
            if lhs.rate != rhs.rate { return (lhs.rate ?? -1) > (rhs.rate ?? -1) }
            return lhs.title < rhs.title
        }
    }

    /// The quarterly bonus, including the two states that are not a bonus at
    /// all. "Nobody has published this quarter" is a different sentence from
    /// "nothing extra this quarter", and the app has to be able to say both.
    private static func rotatingBenefit(
        _ program: RotatingProgram,
        on card: Card,
        source: BenefitSource,
        verifiedOn: Date?,
        asOf date: Date
    ) -> CardBenefit {
        let rate = card.currency.formatted(rate: program.rate)
        var title = "\(rate) on a new set of categories each quarter"
        var detail: String?
        var isActive = false

        switch program.status(for: Quarter.containing(date)) {
        case .bonus(let quarter):
            title = "\(rate) on this quarter's categories"
            detail = quarter.summary ?? quarter.categories.map(\.displayName).joined(separator: ", ")
            if !quarter.isActivated {
                detail = [detail, "You are not earning it until you switch it on with the issuer."]
                    .compactMap { $0 }
                    .joined(separator: " ")
            }
            isActive = quarter.isActivated
        case .unannounced:
            detail = "CardWise has not verified this quarter's categories. Check your issuer."
        case .none:
            detail = "Nothing extra on this card this quarter."
        }

        return CardBenefit(
            origin: .rotating,
            group: .creditsAndBonuses,
            kind: .rotatingRate,
            title: title,
            detail: detail,
            rate: program.rate,
            cap: program.cap,
            source: source,
            verifiedOn: verifiedOn,
            isActive: isActive,
            // The issuer owns this one. Switching it off here would only hide
            // it from the person it is being kept honest for.
            isRemovable: true
        )
    }

    private static func welcomeBenefit(
        _ bonus: WelcomeBonus,
        on card: Card,
        source: BenefitSource,
        verifiedOn: Date?,
        asOf date: Date
    ) -> CardBenefit {
        let payout: String
        switch card.currency.style {
        case .percent:
            // A cash back unit is one cent — see `WelcomeBonus.rewardUnits`,
            // and `RecommendationEngine.welcomeBonusBoost`, which values it
            // the same way. Printing the units as dollars read "$20,000 back"
            // for a $200 bonus.
            payout = "\(RecommendationEngine.dollars(Decimal(bonus.rewardUnits / 100))) back"
        case .multiplier:
            payout = "\(units(bonus.rewardUnits)) \(card.currency.name)"
        }
        let target = RecommendationEngine.dollars(bonus.requiredSpendDollars)

        return CardBenefit(
            origin: .welcomeBonus,
            group: .creditsAndBonuses,
            kind: .bonus,
            title: "Signup bonus: \(payout)",
            detail: bonus.isMet
                ? "Earned. Nothing left to spend."
                : "\(RecommendationEngine.dollars(bonus.remainingSpendDollars)) of the \(target) still to spend.",
            source: source,
            verifiedOn: verifiedOn,
            expiresOn: bonus.deadline,
            isActive: bonus.isOpen(asOf: date)
        )
    }

    /// "60,000 Membership Rewards". The locale is pinned rather than taken
    /// from the device, because Linux CI runs with no locale at all and the
    /// separator would quietly vanish there and nowhere else.
    private static func units(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US")
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? String(Int(value))
    }
}

extension Perk {
    /// A travel credit and a cash-back match are money, not perks, and belong
    /// beside the signup bonus rather than in a list of insurances.
    public var benefitGroup: BenefitGroup {
        switch self {
        case .annualTravelCredit, .firstYearCashbackMatch: return .creditsAndBonuses
        default: return .cardPerks
        }
    }

    public var benefitKind: BenefitKind {
        switch self {
        case .noForeignTransactionFee: return .perk
        case .loungeAccess: return .access
        case .annualTravelCredit: return .credit
        case .firstYearCashbackMatch: return .bonus
        case .tripDelayInsurance, .tripCancellationInsurance, .rentalCarCDW,
             .purchaseProtection, .extendedWarranty, .cellPhoneProtection:
            return .insurance
        }
    }
}

// MARK: - Writing a change back

extension Card {

    /// Drops a benefit the user says their card does not have.
    ///
    /// The correction goes into the structures the ranking engine already
    /// reads, never into a parallel list of exceptions — so a card the user has
    /// corrected is ranked on what they corrected it to, with no second code
    /// path to keep in step. Anything the origin does not name is untouched:
    /// removing a dining rate must not disturb a cap, a perk or the pin.
    public func removingBenefit(_ benefit: CardBenefit) -> Card {
        guard benefit.isRemovable else { return self }
        var card = self
        card.adjustedBenefitIDs = Array(Set((card.adjustedBenefitIDs ?? []) + [benefit.id]))
        switch benefit.origin {
        case .rule(let category):
            guard category != .base else { return self }
            card.rules.removeAll { $0.category == category }
        case .perk(let perk):
            card.perks.removeAll { $0 == perk }
        case .welcomeBonus:
            card.welcomeBonus = nil
        case .rotating:
            card.rotatingProgram = nil
        }
        return card
    }

    /// The card as it is after the user unticked some rows. Ids are passed
    /// rather than the benefits themselves so a redraw between tap and save
    /// cannot drop the wrong row.
    public func removingBenefits(ids: Set<String>, asOf date: Date = Date()) -> Card {
        guard !ids.isEmpty else { return self }
        var card = self
        for benefit in CardBenefit.benefits(for: self, asOf: date) where ids.contains(benefit.id) {
            card = card.removingBenefit(benefit)
        }
        return card
    }

    /// Everything this card is good for, in words. Convenience for the views.
    public func benefits(asOf date: Date = Date()) -> [CardBenefit] {
        CardBenefit.benefits(for: self, asOf: date)
    }
}
