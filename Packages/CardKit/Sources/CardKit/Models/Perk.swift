import Foundation

/// Benefits that are not an earn rate. These are what matter in travel mode.
public enum Perk: String, Codable, CaseIterable, Sendable, Hashable {
    case noForeignTransactionFee
    case tripDelayInsurance
    case tripCancellationInsurance
    case rentalCarCDW
    case loungeAccess
    case annualTravelCredit
    case purchaseProtection
    case extendedWarranty
    case cellPhoneProtection
    case firstYearCashbackMatch

    public var displayName: String {
        switch self {
        case .noForeignTransactionFee: return "No foreign transaction fee"
        case .tripDelayInsurance: return "Trip delay insurance"
        case .tripCancellationInsurance: return "Trip cancellation insurance"
        case .rentalCarCDW: return "Rental car damage waiver"
        case .loungeAccess: return "Airport lounge access"
        case .annualTravelCredit: return "Annual travel credit"
        case .purchaseProtection: return "Purchase protection"
        case .extendedWarranty: return "Extended warranty"
        case .cellPhoneProtection: return "Cell phone protection"
        case .firstYearCashbackMatch: return "First-year cash back match"
        }
    }

    public var isTravelRelevant: Bool {
        switch self {
        case .noForeignTransactionFee, .tripDelayInsurance, .tripCancellationInsurance,
             .rentalCarCDW, .loungeAccess, .annualTravelCredit:
            return true
        default:
            return false
        }
    }
}
