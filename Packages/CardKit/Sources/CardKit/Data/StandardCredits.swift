import Foundation

/// Public credits are visible without implying account enrollment or known usage.
/// Account-specific confirmations and redemption history live on the wallet copy.
public enum StandardCredits {
    public static func offers(productID: String, source: String, verifiedOn: Date) -> [PersonalOffer] {
        func credit(_ number: Int, _ title: String, _ amount: Decimal, _ merchants: [String], _ recurrence: OfferRecurrence, online: Bool = false) -> PersonalOffer {
            var offer = PersonalOffer()
            offer.id = UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", number))!
            offer.title = title; offer.scope = .partners; offer.merchantNames = merchants
            offer.reward = .credit; offer.value = amount; offer.maximumReward = amount
            offer.recurrence = recurrence; offer.usesPerPeriod = 1000
            offer.channel = online ? .online : .both
            offer.enrollmentRequired = true; offer.enrolled = false
            offer.stacking = .unknown; offer.enabled = false
            offer.catalogBenefitID = "\(productID).credit.\(number)"
            offer.sourceURL = source; offer.verifiedOn = verifiedOn
            return offer
        }
        switch productID {
        case "amex-gold":
            return [
                credit(1, "Gold dining credit · eligible partners only", 10, ["Grubhub", "Seamless", "Buffalo Wild Wings", "Five Guys", "The Cheesecake Factory", "Wonder"], .monthly),
                credit(2, "Gold Dunkin' credit · U.S. only", 7, ["Dunkin'", "Dunkin"], .monthly)
            ]
        case "amex-blue-cash-preferred":
            return [credit(3, "Disney streaming credit · direct U.S. subscriptions only", 10, ["DisneyPlus.com", "Hulu.com", "Stream.ESPN.com"], .monthly, online: true)]
        default: return []
        }
    }
}
