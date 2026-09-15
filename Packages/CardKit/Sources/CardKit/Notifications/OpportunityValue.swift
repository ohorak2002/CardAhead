import Foundation

/// How much a suggestion is probably worth, in cents, for the sole purpose of
/// ranking one interruption against another.
///
/// **This number is never shown to anybody and must never become a claim.**
/// The app has a hard rule that it does not report rewards it has not been
/// told about — `BenefitValueCalculator` prices a suggestion only once
/// somebody volunteers what they actually spent, and `ImpactView` reports
/// nothing until they do. That rule is intact. This is a different quantity
/// with a different job: at the moment a geofence fires, the app must choose
/// between staying quiet and interrupting somebody, and "is this a fifteen
/// cent decision or a twenty dollar one" is the question that makes the
/// choice. Refusing to estimate does not avoid the judgement, it just makes
/// it badly — a cents-per-dollar edge alone says a coffee and a hotel are
/// worth the same, which is obviously false and is exactly the mistake that
/// makes an app feel stupid.
///
/// So: an internal sort key, with a test asserting the ordering is sane, and
/// a doc comment saying it may not leave this layer.
public enum OpportunityValue {

    /// What one purchase in this category tends to cost, in dollars.
    ///
    /// **Deliberately coarse, and deliberately not per-user.** These are
    /// order-of-magnitude separations — a coffee, a weekly shop, a flight —
    /// and their only job is to keep those three from being ranked as equals.
    /// Tightening them towards a real average would imply a precision that a
    /// fixed table cannot have, and personalising them would mean keeping a
    /// record of what somebody spends where, which is the thing
    /// `ImpactEvent` refuses to hold.
    ///
    /// Transit is the one that looks wrong and is not: a fare is a few
    /// dollars, so a transit reminder has to clear the bar on the strength of
    /// the rate rather than the size of the bill.
    public static func typicalTicketDollars(for category: SpendingCategory) -> Double {
        switch category {
        case .base: return 40
        case .dining: return 35
        case .groceries: return 90
        case .warehouseClub: return 130
        case .gas: return 45
        case .drugstores: return 25
        case .travel: return 200
        case .travelPortal: return 400
        case .flights: return 350
        case .hotels: return 250
        case .transit: return 6
        case .rideshare: return 25
        case .streaming: return 15
        case .entertainment: return 45
        case .onlineShopping: return 60
        case .homeImprovement: return 80
        case .departmentStore: return 60
        }
    }

    /// The edge over the next best card, priced at a typical ticket for this
    /// kind of shop.
    ///
    /// Uses the *incremental* figure — what the recommended card earns over
    /// the best other card already in the wallet — for the same reason the
    /// impact ledger does: a 4x card earns 4x whether or not anything told
    /// you about it, so what a reminder is worth is the gap, never the total.
    /// A wallet of one card has no gap and no alternative; the suggestion is
    /// then worth whatever the card earns, because without it the purchase
    /// might have gone on something that is not in the wallet at all.
    public static func estimatedCents(
        edgeCentsPerDollar: Double,
        category: SpendingCategory
    ) -> Double {
        max(0, edgeCentsPerDollar) * typicalTicketDollars(for: category)
    }
}
