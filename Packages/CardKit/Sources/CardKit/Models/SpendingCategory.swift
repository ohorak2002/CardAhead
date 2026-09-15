import Foundation

/// A bucket a purchase falls into. Every earn rule on a card is written
/// against one of these, and every merchant we resolve maps onto one.
public enum SpendingCategory: String, Codable, CaseIterable, Sendable, Hashable {
    case base
    case dining
    case groceries
    case warehouseClub
    case gas
    case drugstores
    case travel
    case travelPortal
    case flights
    case hotels
    case transit
    case rideshare
    case streaming
    case entertainment
    case onlineShopping
    case homeImprovement
    case departmentStore

    public var displayName: String {
        switch self {
        case .base: return "Everything else"
        case .dining: return "Dining"
        case .groceries: return "Groceries"
        case .warehouseClub: return "Warehouse club"
        case .gas: return "Gas"
        case .drugstores: return "Drugstores"
        case .travel: return "Travel"
        case .travelPortal: return "Travel booked through the issuer"
        case .flights: return "Flights"
        case .hotels: return "Hotels"
        case .transit: return "Transit"
        case .rideshare: return "Rideshare"
        case .streaming: return "Streaming"
        case .entertainment: return "Entertainment"
        case .onlineShopping: return "Online shopping"
        case .homeImprovement: return "Home improvement"
        case .departmentStore: return "Department stores"
        }
    }

    /// How a person says it out loud, as the tail of a sentence starting with
    /// a rate: "4x at restaurants", "1% on everything else". The Benefits
    /// screen is the whole reason this exists — nobody should have to read
    /// "CategoryRule(category: .dining, rate: 4)" to understand their card.
    public var benefitPhrase: String {
        switch self {
        case .base: return "on everything else"
        case .dining: return "at restaurants"
        case .groceries: return "at supermarkets"
        case .warehouseClub: return "at warehouse clubs"
        case .gas: return "at gas stations"
        case .drugstores: return "at drugstores"
        case .travel: return "on travel"
        case .travelPortal: return "on travel booked through the issuer"
        case .flights: return "on flights"
        case .hotels: return "on hotels"
        case .transit: return "on transit"
        case .rideshare: return "on rideshare"
        case .streaming: return "on streaming"
        case .entertainment: return "on entertainment"
        case .onlineShopping: return "on online shopping"
        case .homeImprovement: return "at home improvement stores"
        case .departmentStore: return "at department stores"
        }
    }

    /// What kind of *place* this is, as the head of a lock-screen title:
    /// "Gas station nearby", "Restaurant nearby".
    ///
    /// **Deliberately not `displayName`.** `displayName` names the bucket a
    /// card pays on — "Dining", "Drugstores" — which is the right word on the
    /// Benefits screen and the wrong one on a lock screen, where nobody is
    /// standing outside a "Dining". This is the noun a person would use for
    /// the building in front of them. Same two-axes discipline as
    /// `MapCategory` vs `SpendingCategory`: what a shop *is* and what a card
    /// *pays there* are not one word.
    ///
    /// The categories that have no building (`streaming`, `onlineShopping`,
    /// `travelPortal`, `base`) still get an honest phrase rather than a
    /// placeholder, because a geofence for one is not impossible, only odd.
    public var placePhrase: String {
        switch self {
        case .base: return "Store"
        case .dining: return "Restaurant"
        case .groceries: return "Grocery store"
        case .warehouseClub: return "Warehouse club"
        case .gas: return "Gas station"
        case .drugstores: return "Pharmacy"
        case .travel: return "Travel"
        case .travelPortal: return "Travel booking"
        case .flights: return "Airport"
        case .hotels: return "Hotel"
        case .transit: return "Transit"
        case .rideshare: return "Rideshare"
        case .streaming: return "Streaming"
        case .entertainment: return "Entertainment"
        case .onlineShopping: return "Online shopping"
        case .homeImprovement: return "Hardware store"
        case .departmentStore: return "Department store"
        }
    }

    /// One emoji, and never more than one, for the front of a notification
    /// title.
    ///
    /// **A lock screen is a list of grey rectangles and the eye picks the
    /// coloured thing first.** The app icon is already there but it is the
    /// same icon on every reminder, so it says "CardWise" and nothing about
    /// *this* one. The emoji says what kind of place before a single word is
    /// read, which is the only job the first glance can do.
    ///
    /// Emoji, not an SF Symbol, because a title is text and text cannot hold
    /// a symbol. The coloured badge on the trailing edge — see
    /// `ReminderBadge` in the app — is where the symbol goes.
    public var emoji: String {
        switch self {
        case .base: return "💳"
        case .dining: return "🍽️"
        case .groceries: return "🛒"
        case .warehouseClub: return "📦"
        case .gas: return "⛽️"
        case .drugstores: return "💊"
        case .travel: return "✈️"
        case .travelPortal: return "🧳"
        case .flights: return "🛫"
        case .hotels: return "🏨"
        case .transit: return "🚇"
        case .rideshare: return "🚗"
        case .streaming: return "📺"
        case .entertainment: return "🎟️"
        case .onlineShopping: return "🛍️"
        case .homeImprovement: return "🔨"
        case .departmentStore: return "🏬"
        }
    }

    /// Categories that only make sense while the user is away from home.
    public var isTravelRelated: Bool {
        switch self {
        case .travel, .travelPortal, .flights, .hotels, .rideshare, .transit: return true
        default: return false
        }
    }
}
