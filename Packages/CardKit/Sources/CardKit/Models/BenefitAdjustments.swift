import Foundation

/// The standard version accepted by this wallet. Updates are reviewed, never silently
/// overwrite user edits, and legacy wallets remain intact until review.
public struct CatalogBaseline: Codable, Hashable, Sendable {
    public var rules: [CategoryRule]
    public var perks: [Perk]
    public var checkedOn: Date
    public init(rules: [CategoryRule], perks: [Perk], checkedOn: Date) {
        self.rules = rules; self.perks = perks; self.checkedOn = checkedOn
    }
}

extension Card {
    public func isUserAdjusted(_ origin: BenefitOrigin) -> Bool {
        guard catalogProductID != nil else { return true }
        if adjustedBenefitIDs?.contains(origin.identifier) == true { return true }
        guard let baseline = catalogBaseline else { return true } // old terms not re-certified
        switch origin {
        case .rule(let category):
            guard let current = rule(for: category), let standard = baseline.rules.first(where: { $0.category == category }) else { return true }
            return current.rate != standard.rate || current.note != standard.note
                || current.cap?.limitDollars != standard.cap?.limitDollars || current.cap?.period != standard.cap?.period
        case .perk(let perk): return !baseline.perks.contains(perk)
        case .welcomeBonus: return true
        case .rotating: return rotatingUserProvided ?? false
        }
    }

    public mutating func restoreBenefit(_ origin: BenefitOrigin) {
        guard let standard = CardCatalog.entry(for: self)?.card else { return }
        switch origin {
        case .rule(let category):
            let usage = rule(for: category)?.cap
            rules.removeAll { $0.category == category }
            if var rule = standard.rule(for: category) {
                if let usage { rule.cap?.spentDollars = usage.spentDollars; rule.cap?.usageUpdatedOn = usage.usageUpdatedOn }
                rules.append(rule)
            }
        case .perk(let perk): if standard.perks.contains(perk) && !perks.contains(perk) { perks.append(perk) }
        case .rotating: rotatingProgram = standard.rotatingProgram; rotatingUserProvided = false
        case .welcomeBonus: return
        }
        adjustedBenefitIDs?.removeAll { $0 == origin.identifier }
    }

    public var hasCatalogUpdate: Bool {
        guard let entry = CardCatalog.entry(for: self) else { return false }
        return catalogBaseline?.checkedOn != entry.checkedOn
    }

    public mutating func reviewCatalogUpdate() {
        guard let entry = CardCatalog.entry(for: self) else { return }
        // Classify against the old accepted version BEFORE replacing it.
        let origins = Set((catalogBaseline?.rules ?? rules).map { BenefitOrigin.rule($0.category) }
            + (catalogBaseline?.perks ?? perks).map { BenefitOrigin.perk($0) })
        for origin in origins {
            if isUserAdjusted(origin) || (adjustedBenefitIDs ?? []).contains(origin.identifier) {
                if adjustedBenefitIDs == nil { adjustedBenefitIDs = [] }
                if !adjustedBenefitIDs!.contains(origin.identifier) { adjustedBenefitIDs!.append(origin.identifier) }
            } else { restoreBenefit(origin) }
        }
        catalogBaseline = entry.card.catalogBaseline
    }
}
