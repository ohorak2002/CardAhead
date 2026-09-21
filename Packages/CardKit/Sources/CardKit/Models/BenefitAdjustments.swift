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
        case .rotating: return (rotatingUserProvided ?? false) || rotatingProgram?.quarters.contains(where: { $0.enteredByUser }) == true
        }
    }

    public mutating func restoreBenefit(_ origin: BenefitOrigin) {
        guard let standard = CardCatalog.entry(for: self)?.card else { return }
        // Certify only the restored item. Other legacy terms still need review.
        if catalogBaseline == nil {
            adjustedBenefitIDs = Array(Set((adjustedBenefitIDs ?? [])
                + rules.map { BenefitOrigin.rule($0.category).identifier }
                + perks.map { BenefitOrigin.perk($0).identifier }))
            catalogBaseline = CatalogBaseline(rules: [], perks: [], checkedOn: .distantPast)
        }
        switch origin {
        case .rule(let category):
            let usage = rule(for: category)?.cap
            rules.removeAll { $0.category == category }
            if var rule = standard.rule(for: category) {
                if let usage { rule.cap?.spentDollars = usage.spentDollars; rule.cap?.usageUpdatedOn = usage.usageUpdatedOn }
                rules.append(rule)
            }
            catalogBaseline?.rules.removeAll { $0.category == category }
            if let rule = standard.rule(for: category) { catalogBaseline?.rules.append(rule) }
        case .perk(let perk): if standard.perks.contains(perk) && !perks.contains(perk) { perks.append(perk) }
        case .rotating: rotatingProgram = standard.rotatingProgram; rotatingUserProvided = false
        case .welcomeBonus: return
        }
        if case .perk(let perk) = origin, standard.perks.contains(perk), catalogBaseline?.perks.contains(perk) == false {
            catalogBaseline?.perks.append(perk)
        }
        adjustedBenefitIDs?.removeAll { $0 == origin.identifier }
    }

    public var hasCatalogUpdate: Bool {
        guard let entry = CardCatalog.entry(for: self) else { return false }
        return catalogBaseline?.checkedOn != entry.checkedOn
    }

    public mutating func reviewCatalogUpdate() {
        guard let entry = CardCatalog.entry(for: self) else { return }
        let previousBaseline = catalogBaseline
        // Classify against the old accepted version BEFORE replacing it.
        let origins = Set((catalogBaseline?.rules ?? rules).map { BenefitOrigin.rule($0.category) }
            + (catalogBaseline?.perks ?? perks).map { BenefitOrigin.perk($0) })
        for origin in origins {
            if isUserAdjusted(origin) || (adjustedBenefitIDs ?? []).contains(origin.identifier) {
                if adjustedBenefitIDs == nil { adjustedBenefitIDs = [] }
                if !adjustedBenefitIDs!.contains(origin.identifier) { adjustedBenefitIDs!.append(origin.identifier) }
            } else { restoreBenefit(origin) }
        }
        // A newly published category can be added only when this card had an
        // accepted baseline; legacy omissions may be intentional personal terms.
        if let previousBaseline {
            for rule in entry.card.rules where !previousBaseline.rules.contains(where: { $0.category == rule.category }) {
                let origin = BenefitOrigin.rule(rule.category)
                if self.rule(for: rule.category) == nil && !(adjustedBenefitIDs ?? []).contains(origin.identifier) {
                    restoreBenefit(origin)
                }
            }
        }
        if standardBenefitOffers == nil { standardBenefitOffers = entry.card.standardBenefitOffers }
        catalogBaseline = entry.card.catalogBaseline
    }
}
