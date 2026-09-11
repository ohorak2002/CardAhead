import Foundation

/// A business at a place, already resolved to a spending category.
///
/// The `id` is whichever place provider produced it, so the same shop keeps the
/// same identity across refreshes and a geofence for it can be recognised again
/// after iOS relaunches the app.
public struct Merchant: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var coordinate: GeoCoordinate
    /// Raw provider types, kept so confidence can be re-derived without another
    /// network call, and so a mis-mapping is debuggable from a log line.
    public var placeTypes: [String]
    public var category: SpendingCategory
    /// A mall or an airport cannot be resolved to one till, so the reminder
    /// names the category rather than the shop. See `MerchantCategoryMap`.
    public var confidence: MerchantConfidence

    public init(
        id: String,
        name: String,
        coordinate: GeoCoordinate,
        placeTypes: [String] = [],
        category: SpendingCategory,
        confidence: MerchantConfidence = .exact
    ) {
        self.id = id
        self.name = name
        self.coordinate = coordinate
        self.placeTypes = placeTypes
        self.category = category
        self.confidence = confidence
    }

    /// Builds a merchant from raw provider output, or nothing when the types do
    /// not map onto a category we can rank. Guessing a category is worse than
    /// staying quiet: a wrong nudge costs the user the reward it promised.
    public static func from(
        id: String,
        name: String,
        coordinate: GeoCoordinate,
        placeTypes: [String]
    ) -> Merchant? {
        guard let category = MerchantCategoryMap.category(
            forPlaceTypes: placeTypes,
            merchantName: name
        ) else { return nil }

        return Merchant(
            id: id,
            name: name,
            coordinate: coordinate,
            placeTypes: placeTypes,
            category: category,
            confidence: MerchantCategoryMap.confidence(forPlaceTypes: placeTypes)
        )
    }
}
