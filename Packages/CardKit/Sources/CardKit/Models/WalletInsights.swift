import Foundation

/// One benefit, and which card in the wallet it belongs to.
///
/// The Benefits screen reads across the whole wallet rather than down one
/// card, which is the question people actually have: not "what does my Gold
/// do" but "what am I carrying for dining".
public struct WalletBenefit: Identifiable, Hashable, Sendable {
    public var id: String { "\(cardID.uuidString).\(benefit.id)" }
    public var cardID: UUID
    public var cardName: String
    public var benefit: CardBenefit

    public init(cardID: UUID, cardName: String, benefit: CardBenefit) {
        self.cardID = cardID
        self.cardName = cardName
        self.benefit = benefit
    }
}

/// A shelf on the Benefits screen: one category, every card's contribution to
/// it, and how much of it is actually paying right now.
public struct BenefitGroupSummary: Identifiable, Hashable, Sendable {
    public var id: BenefitGroup { group }
    public var group: BenefitGroup
    public var benefits: [WalletBenefit]

    public init(group: BenefitGroup, benefits: [WalletBenefit]) {
        self.group = group
        self.benefits = benefits
    }

    /// Paying right now. The count the screen leads with, because a benefit
    /// whose cap is spent or whose quarter was never switched on is not
    /// something anybody "has" this month.
    public var activeCount: Int { benefits.filter(\.benefit.isActive).count }
    public var totalCount: Int { benefits.count }

    /// The best rate anybody in the wallet pays in this category.
    public var bestRate: Double? {
        benefits.filter(\.benefit.isActive).compactMap(\.benefit.rate).max()
    }

    /// "4x", "4%" — or nothing at all.
    ///
    /// Nothing when the cards on this shelf state their rates in different
    /// units, because there is then no honest way to write one number. A 4x
    /// points card and a 4% cash back card are not the same offer, and "up to
    /// 4" on a tile invites the reader to decide which one it meant. A tile
    /// with no number on it is worse-looking and not wrong.
    public func bestRateText(in wallet: [Card]) -> String? {
        guard let rate = bestRate else { return nil }
        let earning = benefits.filter(\.benefit.isActive).compactMap { entry in
            wallet.first { $0.id == entry.cardID }?.currency.style
        }
        let styles = Set(earning)
        guard let style = styles.first, styles.count == 1 else { return nil }
        let number = rate == rate.rounded() ? String(Int(rate)) : String(format: "%.1f", rate)
        return style == .percent ? "\(number)%" : "\(number)x"
    }

    // MARK: - The line that is always true

    /// What a shelf can say about itself when a number would be dishonest.
    ///
    /// **This exists because `bestRateText` is nil most of the time, and that
    /// is correct.** Five of a seven-shelf wallet mix a points card and a cash
    /// back card, so five tiles had no number on them and two did — which
    /// reads as a rendering fault rather than as restraint. The fix is not to
    /// invent a comparison between 4x and 3%; it is to give every shelf a
    /// third line that is worth reading whether or not a number is available.
    ///
    /// The order is a priority, not a taste: anything needing attention
    /// outranks anything merely informative, because the whole point of a
    /// rewards organiser is that the thing about to lapse finds *you*.
    public enum Lead: Hashable, Sendable {
        /// Something here has a real deadline inside the window.
        case endsSoon
        /// A rotating bonus nobody has switched on. Doing nothing costs money.
        case needsSwitchingOn
        /// One card is the reason you have this shelf.
        case bestWith(String)
        /// Several cards contribute and none is the obvious lead.
        case severalCards(Int)
        /// The shelf exists on paper but nothing on it is paying.
        case nothingPaying
    }

    /// The shelf's own headline, in priority order. See `Lead`.
    ///
    /// `expiringSoon` is passed in rather than recomputed because the screen
    /// has already built it for its own "Running out" list, and walking every
    /// card's benefits a second time per tile is work for nothing.
    public func lead(expiring: Set<String> = []) -> Lead {
        if benefits.contains(where: { expiring.contains($0.id) }) { return .endsSoon }

        // A rotating benefit that is present but not active is, in this model,
        // exactly the "switched off" case — `CardBenefit.isActive` is false
        // for an unactivated quarter.
        if benefits.contains(where: { $0.benefit.origin == .rotating && !$0.benefit.isActive }) {
            return .needsSwitchingOn
        }

        let active = benefits.filter(\.benefit.isActive)
        guard !active.isEmpty else { return .nothingPaying }

        let names = Set(active.map(\.cardName))
        if names.count == 1, let only = names.first { return .bestWith(only) }

        // Several cards pay here. One of them leads only if it pays strictly
        // more than the rest *in the same units* — otherwise naming a "best"
        // is the comparison this whole type exists to avoid.
        let rated = active.filter { $0.benefit.rate != nil }
        if let top = rated.max(by: { ($0.benefit.rate ?? 0) < ($1.benefit.rate ?? 0) }),
           let topRate = top.benefit.rate,
           rated.filter({ $0.benefit.rate == topRate }).count == 1,
           Set(rated.map(\.cardName)).count > 1 {
            return .bestWith(top.cardName)
        }
        return .severalCards(names.count)
    }
}

public extension BenefitGroupSummary.Lead {
    /// The words themselves, so the phrasing lives next to the rule that
    /// chose it rather than in a `switch` inside a view.
    var text: String {
        switch self {
        case .endsSoon: return "Ends soon"
        case .needsSwitchingOn: return "Needs switching on"
        case .bestWith(let card): return "Best with \(card)"
        case .severalCards(let count): return "\(count) cards pay here"
        case .nothingPaying: return "Nothing paying now"
        }
    }

    /// Whether this is something to do rather than something to know. Drives
    /// the colour, and nothing else — the wording stands on its own for
    /// anybody who cannot tell the two apart.
    var needsAttention: Bool {
        switch self {
        case .endsSoon, .needsSwitchingOn: return true
        case .bestWith, .severalCards, .nothingPaying: return false
        }
    }
}

/// Things worth saying about a whole wallet rather than about one card.
///
/// All of it derived, none of it stored — same rule as `CardBenefit`. A second
/// copy of what the wallet contains is a second thing to keep in step with the
/// ranking engine, and the two disagreeing is the bug nobody can find from a
/// screenshot.
public enum WalletInsights {

    // MARK: - What each card is for

    /// The category this card is the best one in the wallet for.
    ///
    /// The wallet row says "Best for Dining", and that has to be *true of this
    /// wallet* rather than true in general — a 3x dining card sitting beside a
    /// 4x dining card is not what you should reach for at a restaurant, and
    /// labelling it "best for dining" would be the app telling a small lie on
    /// every scroll.
    ///
    /// Nil when the card wins nothing, which is a real answer: it means
    /// another card in the wallet covers everything this one does.
    ///
    /// **`card` must be an element of `wallet`.** Winning is decided by `id`,
    /// and `CardCatalog`'s properties are computed — every access mints a new
    /// one — so passing `CardCatalog.amexGold` alongside a wallet built from
    /// another `CardCatalog.amexGold` compares two different cards and always
    /// answers nil. CI found this before a human did; there is a test named
    /// after it.
    public static func bestCategory(
        for card: Card,
        in wallet: [Card],
        asOf date: Date = Date(),
        engine: RecommendationEngine = RecommendationEngine()
    ) -> SpendingCategory? {
        func wins(_ category: SpendingCategory) -> Bool {
            let context = PurchaseContext(category: category, confidence: .exact, date: date)
            guard let best = engine.rank(wallet, in: context).first, best.card.id == card.id else { return false }
            return category == .base || best.appliedRate > card.baseRate
        }

        // Its own bonus categories first, best-paying one leading — that is the
        // headline anybody would pick for the card themselves.
        let bonuses = card.bonusCategories(asOf: date)
            .sorted {
                let left = engine.score(card, in: PurchaseContext(category: $0, date: date)).effectiveCentsPerDollar
                let right = engine.score(card, in: PurchaseContext(category: $1, date: date)).effectiveCentsPerDollar
                return left == right ? $0.rawValue < $1.rawValue : left > right
            }

        if let won = bonuses.first(where: wins) { return won }

        // A flat card with no bonus anywhere can still be the one you reach
        // for by default, and "best for everything else" is what that is.
        return wins(.base) ? .base : nil
    }

    /// What a card actually pays in a category, rotating quarter included.
    private static func rate(of card: Card, in category: SpendingCategory, asOf date: Date) -> Double {
        var best = card.rule(for: category)?.rate ?? card.baseRate
        if let program = card.rotatingProgram,
           case .bonus(let quarter) = program.status(for: Quarter.containing(date)),
           quarter.categories.contains(category) {
            best = max(best, program.rate)
        }
        return best
    }

    // MARK: - What the wallet is carrying

    /// Every benefit in the wallet, on the shelf it belongs to, in reading
    /// order. Empty groups are left out rather than shown as zero — a shelf
    /// with nothing on it is not information.
    public static func benefitGroups(
        in wallet: [Card],
        asOf date: Date = Date()
    ) -> [BenefitGroupSummary] {
        var byGroup: [BenefitGroup: [WalletBenefit]] = [:]
        for card in wallet {
            for benefit in card.benefits(asOf: date) {
                byGroup[benefit.group, default: []].append(
                    WalletBenefit(cardID: card.id, cardName: card.displayName, benefit: benefit)
                )
            }
        }
        return byGroup
            .map { BenefitGroupSummary(group: $0.key, benefits: $0.value) }
            .sorted { $0.group.sortOrder < $1.group.sortOrder }
    }

    /// How many benefits across the wallet are paying right now. The number
    /// under the Wallet title: "3 cards · 12 active benefits".
    public static func activeBenefitCount(in wallet: [Card], asOf date: Date = Date()) -> Int {
        wallet.reduce(0) { total, card in
            total + card.benefits(asOf: date).filter(\.isActive).count
        }
    }

    // MARK: - What runs out soon

    /// Benefits with a real deadline inside the window, soonest first.
    ///
    /// **Only benefits that carry a date**, which today means exactly one
    /// thing: an open signup bonus, because its deadline is the only end date
    /// `CardBenefit` actually records. A card's annual travel credit expires
    /// too, and the catalog knows only that the card *has* one — not its size,
    /// its reset date, or whether it has been spent. So it is absent here
    /// rather than given a guessed date. An invented deadline in a list headed
    /// "running out" is the one somebody would rearrange their week around.
    public static func expiringSoon(
        in wallet: [Card],
        asOf date: Date = Date(),
        within window: TimeInterval = 30 * 24 * 60 * 60
    ) -> [WalletBenefit] {
        let deadline = date.addingTimeInterval(window)
        var found: [WalletBenefit] = []

        for card in wallet {
            for benefit in card.benefits(asOf: date) where benefit.isActive {
                guard let expires = benefit.expiresOn, expires > date, expires <= deadline else { continue }
                found.append(WalletBenefit(cardID: card.id, cardName: card.displayName, benefit: benefit))
            }
        }
        return found.sorted {
            ($0.benefit.expiresOn ?? .distantFuture) < ($1.benefit.expiresOn ?? .distantFuture)
        }
    }

    /// Rotating quarters somebody still has to switch on, which is the one
    /// deadline in this app where doing nothing costs real money.
    public static func needingActivation(in wallet: [Card], asOf date: Date = Date()) -> [Card] {
        wallet.filter { card in
            guard let program = card.rotatingProgram else { return false }
            return !program.unactivatedQuarters(asOf: date).isEmpty
        }
    }
}

/// Something worth doing, that doing nothing about costs money.
///
/// The wallet's own to-do list. Deliberately a short one: an opportunity that
/// turns out to be an advert is how a useful surface becomes one nobody looks
/// at, so nothing lands here unless somebody could act on it today and be
/// better off for it.
///
/// **What is not here, and why.** "Your $200 travel credit is unused" is the
/// obvious fourth case and the catalog cannot support it — `Perk` records that
/// a card *has* an annual travel credit, not its size, its reset date or
/// whether it has been spent. Inventing any of those would put a number
/// somebody rearranges their month around behind a guess. It belongs here the
/// day the catalog can say it honestly, and not before.
public struct Opportunity: Identifiable, Hashable, Sendable {

    public enum Kind: String, Sendable, Hashable {
        /// A rotating quarter nobody has switched on. The only case in this
        /// app where doing nothing has a fixed, knowable price.
        case activateRotating
        /// A signup bonus still open, with spend left and a deadline.
        case welcomeBonus
        /// A benefit with a real end date inside the window.
        case expiring
    }

    public var id: String { "\(kind.rawValue).\(cardID.uuidString)" }
    public var kind: Kind
    public var cardID: UUID
    public var cardName: String
    /// One line, in the app's own register: plain, second person, no hype.
    public var title: String
    public var detail: String
    public var category: SpendingCategory?
    /// Sooner is more urgent. Nil when there is no clock on it.
    public var deadline: Date?

    public init(
        kind: Kind,
        cardID: UUID,
        cardName: String,
        title: String,
        detail: String,
        category: SpendingCategory? = nil,
        deadline: Date? = nil
    ) {
        self.kind = kind
        self.cardID = cardID
        self.cardName = cardName
        self.title = title
        self.detail = detail
        self.category = category
        self.deadline = deadline
    }
}

extension WalletInsights {

    /// Everything actionable in the wallet, most urgent first.
    public static func opportunities(
        in wallet: [Card],
        asOf date: Date = Date(),
        within window: TimeInterval = 30 * 24 * 60 * 60
    ) -> [Opportunity] {
        var found: [Opportunity] = []

        for card in wallet {
            if let program = card.rotatingProgram {
                for quarter in program.unactivatedQuarters(asOf: date) {
                    let rate = card.currency.formatted(rate: program.rate)
                    let categories = quarter.categories
                        .map { $0.displayName.lowercased() }
                        .joined(separator: " and ")
                    found.append(Opportunity(
                        kind: .activateRotating,
                        cardID: card.id,
                        cardName: card.displayName,
                        title: "Switch on \(rate) for \(categories)",
                        detail: "Your \(card.displayName) pays it this quarter, once you switch it on.",
                        category: quarter.categories.first,
                        deadline: quarter.quarter.end()
                    ))
                }
            }

            if let bonus = card.welcomeBonus, bonus.isOpen(asOf: date) {
                let left = RecommendationEngine.dollars(bonus.remainingSpendDollars)
                let days = bonus.daysRemaining(asOf: date)
                found.append(Opportunity(
                    kind: .welcomeBonus,
                    cardID: card.id,
                    cardName: card.displayName,
                    title: "\(left) of spend left on your signup bonus",
                    detail: "\(days) days to go on your \(card.displayName).",
                    deadline: bonus.deadline
                ))
            }
        }

        for entry in expiringSoon(in: wallet, asOf: date, within: window)
        where entry.benefit.kind != .bonus {
            found.append(Opportunity(
                kind: .expiring,
                cardID: entry.cardID,
                cardName: entry.cardName,
                title: entry.benefit.title,
                detail: "On your \(entry.cardName).",
                category: entry.benefit.relatedSpendingCategory,
                deadline: entry.benefit.expiresOn
            ))
        }

        return found.sorted {
            ($0.deadline ?? .distantFuture) < ($1.deadline ?? .distantFuture)
        }
    }
}

/// One number and the word under it, for the row of tiles a card detail opens
/// with.
public struct CardStat: Identifiable, Hashable, Sendable {
    public var id: String { label }
    public var value: String
    public var label: String

    public init(value: String, label: String) {
        self.value = value
        self.label = label
    }
}

extension Card {

    /// The two things this card is best at, and what it costs to hold.
    ///
    /// Three tiles, because three is what fits across a phone and because the
    /// third one is the question the first two provoke. Rates are grouped
    /// before they are picked, so a card paying 5x on issuer-booked travel and
    /// 3x on flights offers one travel tile rather than two — the shelf is
    /// what a person recognises, and two tiles saying nearly the same thing is
    /// how a summary stops summarising.
    ///
    /// The base rate is never a headline. Every card has one, so it
    /// distinguishes nothing; a card with no bonus anywhere gets the fee tile
    /// alone, which is the honest summary of such a card.
    public func headlineStats(asOf date: Date = Date()) -> [CardStat] {
        var bestByGroup: [BenefitGroup: (rate: Double, category: SpendingCategory)] = [:]

        for rule in rules where rule.category != .base && rule.rate > baseRate {
            let group = BenefitGroup.containing(rule.category)
            if bestByGroup[group]?.rate ?? 0 < rule.rate {
                bestByGroup[group] = (rule.rate, rule.category)
            }
        }

        if let program = rotatingProgram,
           case .bonus(let quarter) = program.status(for: Quarter.containing(date)),
           let first = quarter.categories.first {
            let group = BenefitGroup.containing(first)
            if bestByGroup[group]?.rate ?? 0 < program.rate {
                bestByGroup[group] = (program.rate, first)
            }
        }

        var stats = bestByGroup
            .sorted { $0.value.rate > $1.value.rate }
            .prefix(2)
            .map { CardStat(value: currency.formatted(rate: $0.value.rate), label: $0.key.displayName) }

        stats.append(CardStat(
            value: RecommendationEngine.dollars(annualFeeDollars),
            label: "Annual fee"
        ))
        return stats
    }
}
