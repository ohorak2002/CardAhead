import Foundation

/// A business on the map.
///
/// **Deliberately not a `Merchant`.** `Merchant` exists to be geofenced, and a
/// geofence around a place we could not resolve to an earning category is a
/// wasted registration out of the twenty iOS allows — which is why
/// `Merchant.from` refuses to build one. The map has the opposite problem: it
/// is a browsing surface, somebody scrolling it wants to see what is actually
/// around them, and a pin that says "nothing in your wallet pays extra here"
/// is a useful answer rather than a gap.
///
/// So `spendingCategory` is optional here and not there, and neither model has
/// to be bent. The two meet at `asMerchant`, for the places that qualify.
public struct MapPlace: Identifiable, Codable, Hashable, Sendable {

    /// The place provider's own id, so the same shop is the same row across a
    /// refresh and a detail lookup can be made for it later.
    public var id: String
    public var name: String
    public var coordinate: GeoCoordinate
    /// Raw provider types. Kept for the same reason `Merchant` keeps them: a
    /// mis-filed place is debuggable from one log line.
    public var placeTypes: [String]
    /// Which filter chip this sits under. Never nil — see `MapCategory.other`.
    public var mapCategory: MapCategory
    /// What a card would earn here, when that is knowable. **Nil is a real
    /// answer**, and the UI says so in words rather than guessing a category.
    public var spendingCategory: SpendingCategory?
    /// A mall or a station cannot be pinned to one till, so a recommendation
    /// for it names the category rather than claiming to know the shop.
    public var confidence: MerchantConfidence

    /// Google's own words for what this is — "Steakhouse", "Fast food
    /// restaurant". Better than anything derivable from the raw type list, and
    /// it is already localised.
    public var typeDescription: String?

    /// A photograph of the actual shop, when the provider has one.
    ///
    /// **Arrives with the search, unlike everything under Detail below.** The
    /// list is where the photograph does its work — it is what turns a column
    /// of names into a column of places you recognise — and a photo that only
    /// appeared after you had already tapped through would be showing you the
    /// place you had by then identified from the name anyway.
    ///
    /// Still just a handle: nothing is downloaded until a view asks for a
    /// specific size. See `PlacePhoto`.
    public var photo: PlacePhoto?

    // MARK: - Detail

    /// Everything below arrives only from a place *details* lookup, which is a
    /// separate and more expensive call than the nearby search. So all of it
    /// is optional and every screen has to read correctly with none of it —
    /// which is also what happens offline, and on a free-tier key.

    public var rating: Double?
    public var ratingCount: Int?
    public var address: String?
    public var isOpenNow: Bool?
    /// Today's line from the provider's own weekday text, e.g.
    /// "11:00 AM – 10:00 PM". Never assembled here out of open/close times:
    /// split shifts and public holidays are exactly what that gets wrong.
    public var hoursToday: String?
    public var phone: String?
    public var website: String?

    public init(
        id: String,
        name: String,
        coordinate: GeoCoordinate,
        placeTypes: [String] = [],
        mapCategory: MapCategory? = nil,
        spendingCategory: SpendingCategory? = nil,
        confidence: MerchantConfidence? = nil,
        typeDescription: String? = nil,
        photo: PlacePhoto? = nil,
        rating: Double? = nil,
        ratingCount: Int? = nil,
        address: String? = nil,
        isOpenNow: Bool? = nil,
        hoursToday: String? = nil,
        phone: String? = nil,
        website: String? = nil
    ) {
        self.id = id
        self.name = name
        self.coordinate = coordinate
        self.placeTypes = placeTypes
        self.mapCategory = mapCategory ?? MapCategory.matching(placeTypes: placeTypes)
        self.spendingCategory = spendingCategory
            ?? MerchantCategoryMap.category(forPlaceTypes: placeTypes, merchantName: name)
        self.confidence = confidence ?? MerchantCategoryMap.confidence(forPlaceTypes: placeTypes)
        self.typeDescription = typeDescription
        self.photo = photo
        self.rating = rating
        self.ratingCount = ratingCount
        self.address = address
        self.isOpenNow = isOpenNow
        self.hoursToday = hoursToday
        self.phone = phone
        self.website = website
    }

    /// What to put under the name when the provider did not name the type
    /// itself: the filter chip it sits under, which is always true if vague.
    public var subtitle: String {
        typeDescription ?? mapCategory.displayName
    }

    /// What the ranking engine needs to know about somebody standing here, or
    /// nothing when no card could be ranked for it.
    ///
    /// Withholds the name for a multi-tenant place for the same reason the
    /// geofence path does — naming the wrong restaurant in the food court is
    /// worse than naming none.
    public func purchaseContext(asOf date: Date = Date()) -> PurchaseContext? {
        guard let spendingCategory else { return nil }
        return PurchaseContext(
            category: spendingCategory,
            merchantName: confidence == .exact ? name : nil,
            confidence: confidence,
            date: date
        )
    }

    /// The geofenceable half of this place, when there is one.
    public var asMerchant: Merchant? {
        guard let spendingCategory else { return nil }
        return Merchant(
            id: id,
            name: name,
            coordinate: coordinate,
            placeTypes: placeTypes,
            category: spendingCategory,
            confidence: confidence
        )
    }

    /// A place the geofence path already knows about, shown on the map.
    /// Used to draw the watched shops even before any map search has run.
    public init(_ merchant: Merchant) {
        self.init(
            id: merchant.id,
            name: merchant.name,
            coordinate: merchant.coordinate,
            placeTypes: merchant.placeTypes,
            spendingCategory: merchant.category,
            confidence: merchant.confidence
        )
    }

    /// Folds a details lookup onto the row the list already has, keeping what
    /// the search gave us where details said nothing.
    public func merging(_ detail: MapPlace) -> MapPlace {
        var merged = self
        merged.typeDescription = detail.typeDescription ?? typeDescription
        // The search's photo is kept when details returned none, so opening a
        // place never *removes* the picture the row was already showing.
        merged.photo = detail.photo ?? photo
        merged.rating = detail.rating ?? rating
        merged.ratingCount = detail.ratingCount ?? ratingCount
        merged.address = detail.address ?? address
        merged.isOpenNow = detail.isOpenNow ?? isOpenNow
        merged.hoursToday = detail.hoursToday ?? hoursToday
        merged.phone = detail.phone ?? phone
        merged.website = detail.website ?? website
        if !detail.placeTypes.isEmpty { merged.placeTypes = detail.placeTypes }
        return merged
    }
}

// MARK: - A place, measured against a wallet

/// One place, how far away it is, and which card wins there.
///
/// Built by `NearbyPlaces.results` rather than assembled in a view, so the
/// filtering, the distance and the ranking are all testable on Linux without a
/// simulator — the same trade the rest of `CardKit` makes.
public struct MapPlaceResult: Identifiable, Sendable, Hashable {
    public var id: String { place.id }
    public var place: MapPlace
    public var distanceMeters: Double
    /// Nil when the place has no earning category, or when the wallet is
    /// empty. Both are ordinary, and both are said out loud in the UI.
    public var recommendation: Recommendation?

    public init(place: MapPlace, distanceMeters: Double, recommendation: Recommendation?) {
        self.place = place
        self.distanceMeters = distanceMeters
        self.recommendation = recommendation
    }

    /// "4x points with American Express Gold". Nil when nothing can be said.
    public var rewardLine: String? {
        guard let best = recommendation?.best else { return nil }
        let rate = best.card.currency.formatted(rate: best.appliedRate)
        return "\(rate) \(best.card.currency.unitNoun) with \(best.card.displayName)"
    }

    /// Whether a card in the wallet pays *more than its everyday rate* here.
    ///
    /// This is what the Home banner counts, so it has to mean something
    /// precise. A wallet of flat-rate cards produces zero opportunities
    /// however many shops are nearby, which is correct: there is nowhere that
    /// walking in changes which card to reach for.
    public var isOpportunity: Bool {
        guard let best = recommendation?.best else { return false }
        if case .base = best.source { return false }
        return true
    }

    public var distanceMiles: Double { distanceMeters / 1_609.344 }

    /// "0.3 mi". Deliberately not `MeasurementFormatter`: it is
    /// locale-dependent and differs between Darwin and Linux, and CardKit is
    /// tested on both — see the currency-formatting bullet in CLAUDE.md.
    public var distanceText: String {
        let miles = distanceMiles
        if miles < 0.1 { return "\(Int((distanceMeters).rounded())) m" }
        return String(format: "%.1f mi", miles)
    }
}

public extension RewardCurrency {
    /// The noun that follows a rate in a sentence: "4x points", "2% back",
    /// "2x miles". Presentational, like `formatted(rate:)`, and on the
    /// currency rather than the card because it is a fact about the currency.
    var unitNoun: String {
        let lowered = name.lowercased()
        if lowered.contains("miles") { return "miles" }
        if style == .percent { return "back" }
        return "points"
    }
}
