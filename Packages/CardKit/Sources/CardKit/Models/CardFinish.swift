import Foundation

/// What the card is physically made of.
///
/// This is not decoration. The app never sees a card number, so recognising a
/// card in the stack depends entirely on it looking like the thing in your
/// wallet — and a brushed metal Amex Gold and a glossy plastic Freedom Flex
/// look nothing alike in the hand.
public enum CardFinish: String, Codable, CaseIterable, Sendable, Hashable {
    case matte
    case glossy
    case metal
    case frosted

    public var displayName: String {
        switch self {
        case .matte: return "Matte"
        case .glossy: return "Glossy"
        case .metal: return "Metal"
        case .frosted: return "Frosted"
        }
    }

    /// How strong the specular highlight across the card should be.
    public var sheenOpacity: Double {
        switch self {
        case .matte: return 0.10
        case .glossy: return 0.30
        case .metal: return 0.42
        case .frosted: return 0.16
        }
    }

    /// How far that highlight spreads either side of its centre, as a fraction
    /// of the card's diagonal.
    ///
    /// This is the half of "material" that opacity alone cannot say. A gloss
    /// throws a **narrow, hard** band, because a smooth surface reflects the
    /// light source almost intact; a matte one scatters the same light into
    /// something **wide and faint**. Vary only the brightness and every card
    /// ends up looking like the same plastic at different exposures.
    public var sheenSpread: Double {
        switch self {
        case .matte: return 0.30
        case .glossy: return 0.11
        case .metal: return 0.15
        case .frosted: return 0.24
        }
    }

    /// Metal cards catch light in fine parallel lines; plastic does not.
    public var isBrushed: Bool { self == .metal }
}
