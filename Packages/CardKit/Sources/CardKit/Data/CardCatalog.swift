import Foundation

/// The seed database the add-card flow searches.
///
/// IMPORTANT: these figures model real, well-known card *structures* so the
/// engine has something realistic to rank. They are not a source of truth.
/// Issuers change rates, caps, and annual fees without notice, and rotating
/// categories are announced a quarter at a time. Verify every number against
/// the issuer terms before shipping, and treat the rotating quarters below as
/// placeholders until they are wired to a real feed.
public enum CardCatalog {

    public static var all: [Card] {
        [
            chaseFreedomFlex,
            chaseSapphirePreferred,
            discoverIt,
            amexBlueCashPreferred,
            amexGold,
            citiDoubleCash,
            capitalOneSavor,
            wellsFargoActiveCash,
            costcoAnywhereVisa
        ]
    }

    public static func search(_ query: String) -> [Card] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return all }
        return all.filter { $0.displayName.lowercased().contains(trimmed) }
    }

    // MARK: - Cards

    public static var chaseFreedomFlex: Card {
        Card(
            issuer: "Chase",
            name: "Freedom Flex",
            currency: .cashBack,
            rules: [
                CategoryRule(category: .dining, rate: 3),
                CategoryRule(category: .drugstores, rate: 3),
                CategoryRule(category: .travelPortal, rate: 5),
                CategoryRule(category: .base, rate: 1)
            ],
            rotatingProgram: RotatingProgram(
                rate: 5,
                cap: EarnCap(limitDollars: 1_500, period: .quarterly),
                quarters: placeholderRotation(
                    q3: [.groceries, .gas],
                    q4: [.departmentStore, .onlineShopping]
                )
            ),
            perks: [.purchaseProtection, .extendedWarranty, .cellPhoneProtection],
            notes: [
                CategoryNote(
                    category: .gas,
                    text: "Placeholder rotating category. Confirm this quarter against Chase before relying on it."
                )
            ],
            foreignTransactionFeePercent: 3,
            annualFeeDollars: 0,
            artKey: "midnight"
        )
    }

    public static var chaseSapphirePreferred: Card {
        Card(
            issuer: "Chase",
            name: "Sapphire Preferred",
            currency: .ultimateRewards,
            rules: [
                CategoryRule(category: .travelPortal, rate: 5),
                CategoryRule(category: .dining, rate: 3),
                CategoryRule(category: .streaming, rate: 3),
                CategoryRule(category: .onlineShopping, rate: 3),
                CategoryRule(category: .travel, rate: 2),
                CategoryRule(category: .flights, rate: 2),
                CategoryRule(category: .hotels, rate: 2),
                CategoryRule(category: .base, rate: 1)
            ],
            perks: [
                .noForeignTransactionFee,
                .tripDelayInsurance,
                .tripCancellationInsurance,
                .rentalCarCDW,
                .annualTravelCredit,
                .purchaseProtection,
                .extendedWarranty
            ],
            foreignTransactionFeePercent: 0,
            annualFeeDollars: 95,
            artKey: "sapphire"
        )
    }

    public static var discoverIt: Card {
        Card(
            issuer: "Discover",
            name: "it Cash Back",
            currency: .cashBack,
            rules: [
                CategoryRule(category: .base, rate: 1)
            ],
            rotatingProgram: RotatingProgram(
                rate: 5,
                cap: EarnCap(limitDollars: 1_500, period: .quarterly),
                quarters: placeholderRotation(
                    q3: [.dining, .gas],
                    q4: [.onlineShopping, .departmentStore]
                )
            ),
            perks: [.firstYearCashbackMatch],
            foreignTransactionFeePercent: 0,
            annualFeeDollars: 0,
            artKey: "graphite"
        )
    }

    public static var amexBlueCashPreferred: Card {
        Card(
            issuer: "Amex",
            name: "Blue Cash Preferred",
            currency: .cashBack,
            rules: [
                CategoryRule(
                    category: .groceries,
                    rate: 6,
                    cap: EarnCap(limitDollars: 6_000, period: .annual),
                    note: "U.S. supermarkets only."
                ),
                CategoryRule(category: .streaming, rate: 6),
                CategoryRule(category: .transit, rate: 3),
                CategoryRule(category: .gas, rate: 3, note: "U.S. gas stations only."),
                CategoryRule(category: .base, rate: 1)
            ],
            notes: [
                CategoryNote(
                    category: .warehouseClub,
                    text: "Warehouse clubs do not code as supermarkets. This card earns its base rate at Costco and Sam's Club."
                ),
                CategoryNote(
                    category: .gas,
                    text: "A gas station with a large convenience store may code as general retail instead of gas."
                )
            ],
            foreignTransactionFeePercent: 2.7,
            annualFeeDollars: 95,
            artKey: "azure"
        )
    }

    public static var amexGold: Card {
        Card(
            issuer: "Amex",
            name: "Gold",
            currency: .membershipRewards,
            rules: [
                CategoryRule(category: .dining, rate: 4),
                CategoryRule(
                    category: .groceries,
                    rate: 4,
                    cap: EarnCap(limitDollars: 25_000, period: .annual),
                    note: "U.S. supermarkets only."
                ),
                CategoryRule(category: .flights, rate: 3),
                CategoryRule(category: .base, rate: 1)
            ],
            perks: [.noForeignTransactionFee, .annualTravelCredit, .purchaseProtection],
            notes: [
                CategoryNote(
                    category: .warehouseClub,
                    text: "Warehouse clubs do not code as supermarkets."
                )
            ],
            foreignTransactionFeePercent: 0,
            annualFeeDollars: 325,
            artKey: "gold"
        )
    }

    public static var citiDoubleCash: Card {
        Card(
            issuer: "Citi",
            name: "Double Cash",
            currency: .cashBack,
            rules: [
                CategoryRule(category: .base, rate: 2, note: "1% when you buy, 1% when you pay it off.")
            ],
            foreignTransactionFeePercent: 3,
            annualFeeDollars: 0,
            artKey: "slate"
        )
    }

    public static var capitalOneSavor: Card {
        Card(
            issuer: "Capital One",
            name: "Savor",
            currency: .cashBack,
            rules: [
                CategoryRule(category: .dining, rate: 3),
                CategoryRule(category: .entertainment, rate: 3),
                CategoryRule(category: .streaming, rate: 3),
                CategoryRule(category: .groceries, rate: 3),
                CategoryRule(category: .base, rate: 1)
            ],
            perks: [.noForeignTransactionFee],
            notes: [
                CategoryNote(
                    category: .warehouseClub,
                    text: "Superstores and warehouse clubs are excluded from the grocery bonus."
                )
            ],
            foreignTransactionFeePercent: 0,
            annualFeeDollars: 0,
            artKey: "ember"
        )
    }

    public static var wellsFargoActiveCash: Card {
        Card(
            issuer: "Wells Fargo",
            name: "Active Cash",
            currency: .cashBack,
            rules: [
                CategoryRule(category: .base, rate: 2)
            ],
            perks: [.cellPhoneProtection],
            foreignTransactionFeePercent: 3,
            annualFeeDollars: 0,
            artKey: "crimson"
        )
    }

    public static var costcoAnywhereVisa: Card {
        Card(
            issuer: "Citi",
            name: "Costco Anywhere Visa",
            currency: .cashBack,
            rules: [
                CategoryRule(
                    category: .gas,
                    rate: 4,
                    cap: EarnCap(limitDollars: 7_000, period: .annual)
                ),
                CategoryRule(category: .dining, rate: 3),
                CategoryRule(category: .travel, rate: 3),
                CategoryRule(category: .warehouseClub, rate: 2),
                CategoryRule(category: .base, rate: 1)
            ],
            perks: [.noForeignTransactionFee],
            notes: [
                CategoryNote(
                    category: .warehouseClub,
                    text: "Rewards arrive once a year as a certificate, not as a statement credit."
                )
            ],
            foreignTransactionFeePercent: 0,
            annualFeeDollars: 0,
            artKey: "forest"
        )
    }

    // MARK: - Rotating placeholders

    /// Rotating categories are announced one quarter at a time, so the seed
    /// database cannot know them. These stand in until a real feed replaces them,
    /// and every card that uses them carries a note saying so.
    static func placeholderRotation(
        q3: [SpendingCategory],
        q4: [SpendingCategory],
        year: Int = 2026
    ) -> [RotatingQuarter] {
        [
            RotatingQuarter(
                quarter: Quarter(year: year, index: 3),
                categories: q3,
                isActivated: false,
                activationDeadline: date(year, 9, 30)
            ),
            RotatingQuarter(
                quarter: Quarter(year: year, index: 4),
                categories: q4,
                isActivated: false,
                activationDeadline: date(year, 12, 31)
            )
        ]
    }

    static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar.date(from: components) ?? Date()
    }
}
