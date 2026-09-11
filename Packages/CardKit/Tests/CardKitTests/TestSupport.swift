import Foundation
@testable import CardKit

enum Fixture {

    /// Mid-August 2026, comfortably inside Q3 so the quarter never flips on a
    /// timezone boundary.
    static let inQ3 = makeDate(2026, 8, 15)
    static let q3 = Quarter(year: 2026, index: 3)

    static func makeDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return Calendar(identifier: .gregorian).date(from: components) ?? Date()
    }

    /// Burn a category cap all the way down.
    static func exhaustingCap(_ card: Card, category: SpendingCategory) -> Card {
        var copy = card
        if let index = copy.rules.firstIndex(where: { $0.category == category }) {
            let limit = copy.rules[index].cap?.limitDollars ?? 0
            copy.rules[index].cap?.spentDollars = limit
        }
        return copy
    }

    static func exhaustingRotatingCap(_ card: Card) -> Card {
        var copy = card
        if var program = copy.rotatingProgram {
            let limit = program.cap?.limitDollars ?? 0
            program.cap?.spentDollars = limit
            copy.rotatingProgram = program
        }
        return copy
    }

    static func activatingRotation(_ card: Card, quarter: Quarter) -> Card {
        var copy = card
        if var program = copy.rotatingProgram,
           let index = program.quarters.firstIndex(where: { $0.quarter == quarter }) {
            program.quarters[index].isActivated = true
            copy.rotatingProgram = program
        }
        return copy
    }

    static func withWelcomeBonus(
        _ card: Card,
        rewardUnits: Double,
        required: Money,
        spent: Money = 0,
        deadline: Date = makeDate(2026, 12, 31)
    ) -> Card {
        var copy = card
        copy.welcomeBonus = WelcomeBonus(
            rewardUnits: rewardUnits,
            requiredSpendDollars: required,
            spentDollars: spent,
            deadline: deadline
        )
        return copy
    }

    static func pinning(_ card: Card) -> Card {
        var copy = card
        copy.isPinned = true
        return copy
    }

    static func valuing(_ card: Card, centsPerUnit: Double) -> Card {
        var copy = card
        copy.currency.centsPerUnit = centsPerUnit
        return copy
    }

    // MARK: - Places

    /// Somewhere in midtown Manhattan, used as the anchor everywhere below so
    /// the offsets in each test read as "a short walk" rather than as numbers.
    static let anchor = GeoCoordinate(latitude: 40.7580, longitude: -73.9855)

    /// A metre of latitude is about 1/111195 of a degree, so a test can say
    /// "300 metres north" and mean it.
    static func offset(_ coordinate: GeoCoordinate, metersNorth: Double) -> GeoCoordinate {
        GeoCoordinate(
            latitude: coordinate.latitude + metersNorth / 111_194.93,
            longitude: coordinate.longitude
        )
    }

    static func merchant(
        _ id: String,
        category: SpendingCategory,
        metersNorth: Double,
        name: String? = nil,
        from origin: GeoCoordinate = Fixture.anchor,
        confidence: MerchantConfidence = .exact
    ) -> Merchant {
        Merchant(
            id: id,
            name: name ?? id.capitalized,
            coordinate: offset(origin, metersNorth: metersNorth),
            category: category,
            confidence: confidence
        )
    }

    static func region(_ merchant: Merchant, distanceMeters: Double = 0) -> MonitoredRegion {
        MonitoredRegion(
            id: RegionPlanner.regionID(for: merchant),
            merchant: merchant,
            radiusMeters: 100,
            distanceMeters: distanceMeters
        )
    }
}
