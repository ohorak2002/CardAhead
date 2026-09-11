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

    /// Categories that only make sense while the user is away from home.
    public var isTravelRelated: Bool {
        switch self {
        case .travel, .travelPortal, .flights, .hotels, .rideshare, .transit: return true
        default: return false
        }
    }
}
