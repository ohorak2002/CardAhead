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

    /// The best rate anybody in the wallet pays in this category, for the
    /// one-line summary: "up to 4x".
    public var bestRate: Double? {
        benefits.filter(\.benefit.isActive).compactMap(\.benefit.rate).max()
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
            return engine.rank(wallet, in: context).first?.card.id == card.id
        }

        // Its own bonus categories first, best-paying one leading — that is the
        // headline anybody would pick for the card themselves.
        let bonuses = card.bonusCategories(asOf: date)
            .sorted { rate(of: card, in: $0, asOf: date) > rate(of: card, in: $1, asOf: date) }

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
