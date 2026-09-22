import Foundation

/// Presentation preferences live outside Card so changing a nickname or hiding
/// a face cannot rewrite a pending notification or alter the recommendation.
public struct WalletOrganization: Codable, Equatable, Sendable {
    public var nicknames: [String: String] = [:]
    public var hiddenCardIDs: Set<UUID> = []
    public var monthlyGoalDollars: Money?

    public init() {}

    public func name(for card: Card) -> String {
        let nickname = nicknames[card.id.uuidString]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return nickname.isEmpty ? card.displayName : nickname
    }

    public mutating func setNickname(_ name: String, for id: UUID) {
        let cleaned = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        nicknames[id.uuidString] = cleaned.isEmpty ? nil : cleaned
    }

    public func visibleCards(in cards: [Card]) -> [Card] {
        cards.filter { !hiddenCardIDs.contains($0.id) }
    }

    public static func goal(from text: String) -> Money? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.range(of: "^[0-9]{1,6}([.,][0-9]{1,2})?$", options: .regularExpression) != nil,
              let value = Decimal(string: trimmed.replacingOccurrences(of: ",", with: "."), locale: Locale(identifier: "en_US_POSIX")),
              value > 0, value <= 100_000 else { return nil }
        return value
    }
}

/// Explanations read the existing score; they never rank a second time or
/// assign a value to an annual fee or an untracked credit.
public extension Recommendation {
    var choiceExplanation: String {
        if best.welcomeBonusBoostCentsPerDollar > 0 {
            return "This purchase helps toward your open signup bonus. \(best.reason)."
        }
        if let other = alternates.first, abs(best.total - other.total) <= RecommendationEngine().tieTolerance {
            return best.card.isPinned && !other.card.isPinned
                ? "Your preferred card breaks a tie in estimated value. \(best.reason)."
                : "Tied for the best estimated value in your wallet. \(best.reason)."
        }
        if alternates.isEmpty { return "Your only card in this wallet. \(best.reason)." }
        return "Highest estimated value for this purchase. \(best.reason)."
    }
}

public struct BenefitDeadline: Identifiable, Hashable, Sendable {
    public var id: String
    public var cardID: UUID
    public var title: String
    public var detail: String
    public var date: Date
    public var needsActivation: Bool

    public func urgency(asOf now: Date, calendar: Calendar = .current) -> String {
        if date < now { return "Ended" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        if days == 0 { return "Ends today" }
        if days == 1 { return "Ends tomorrow" }
        if days <= 14 { return "Ends in \(days) days" }
        if calendar.isDate(date, equalTo: now, toGranularity: .month) { return "Use this month" }
        return "No rush"
    }
}

public enum EverydayInsights {
    public static func deadlines(in cards: [Card], asOf date: Date = Date()) -> [BenefitDeadline] {
        var result: [BenefitDeadline] = []
        for card in cards {
            if let program = card.rotatingProgram {
                for quarter in program.quarters where quarter.quarter >= Quarter.containing(date) && !quarter.categories.isEmpty {
                    let missedActivation = !quarter.isActivated && (quarter.activationDeadline.map { $0 < date } ?? false)
                    if !quarter.isActivated, let activation = quarter.activationDeadline, activation >= date {
                        result.append(BenefitDeadline(id: "\(card.id).activate.\(quarter.id)", cardID: card.id,
                            title: "Switch on your quarterly bonus", detail: "Activation deadline recorded for \(quarter.quarter.rawValue).",
                            date: activation, needsActivation: true))
                    }
                    // The engine's end is exclusive midnight. The timeline
                    // displays the final eligible calendar day, not tomorrow.
                    result.append(BenefitDeadline(
                        id: "\(card.id).rotating.\(quarter.id)", cardID: card.id,
                        title: "Quarterly bonus ends",
                        detail: missedActivation ? "The recorded activation deadline has passed. Check with your bank." : (quarter.isActivated ? "\(card.currency.formatted(rate: program.rate)) on \(quarter.categories.map(\.displayName).joined(separator: ", "))" : "Check activation with your bank before using this bonus."),
                        date: quarter.quarter.end().addingTimeInterval(-1), needsActivation: !quarter.isActivated && !missedActivation
                    ))
                }
            }
            if let bonus = card.welcomeBonus, bonus.isOpen(asOf: date) {
                result.append(BenefitDeadline(
                    id: "\(card.id).welcome", cardID: card.id,
                    title: "Signup bonus deadline",
                    detail: "Spend remaining: $\(NSDecimalNumber(decimal: bonus.remainingSpendDollars).stringValue)",
                    date: bonus.deadline, needsActivation: false
                ))
            }
        }
        return result.filter { $0.date >= date }.sorted {
            $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date
        }
    }

    /// Estimate-entry dates determine the month. No generated, opened, or
    /// unpriced recommendation is counted as rewards earned.
    public static func monthlyImpact(_ ledger: ImpactLedger, asOf date: Date = Date(), calendar: Calendar = .current) -> ImpactSummary {
        guard let month = calendar.dateInterval(of: .month, for: date) else { return ImpactSummary(ImpactLedger()) }
        return ImpactSummary(ImpactLedger(events: ledger.events.filter {
            $0.date >= month.start && $0.date < month.end && $0.date <= date
        }))
    }
}
