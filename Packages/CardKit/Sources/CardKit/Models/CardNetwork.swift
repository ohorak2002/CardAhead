import Foundation

/// The payment network in the corner of the card.
///
/// Deliberately separate from the issuer, because they are different companies
/// and the same bank ships products on more than one: the Freedom Flex is a
/// Chase card on Mastercard, the Costco card is a Citi card on Visa. The
/// selection screen needs this to tell two similar-looking products apart, and
/// so does anyone later matching a card against licensed artwork.
public enum CardNetwork: String, Codable, CaseIterable, Sendable, Hashable {
    case visa
    case mastercard
    case amex
    case discover

    public var displayName: String {
        switch self {
        case .visa: return "Visa"
        case .mastercard: return "Mastercard"
        case .amex: return "American Express"
        case .discover: return "Discover"
        }
    }
}

/// Who a card is sold to.
///
/// "Gold Card" names two different American Express products, one personal and
/// one for businesses, and they do not earn the same way. A catalog that cannot
/// say which one it means will sooner or later hand somebody the wrong rates.
public enum CardVariant: String, Codable, CaseIterable, Sendable, Hashable {
    case personal
    case business

    public var displayName: String {
        switch self {
        case .personal: return "Personal"
        case .business: return "Business"
        }
    }
}
