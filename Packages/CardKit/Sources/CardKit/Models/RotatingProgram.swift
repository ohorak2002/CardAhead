import Foundation

/// One quarter of a rotating bonus program.
public struct RotatingQuarter: Identifiable, Codable, Hashable, Sendable {
    public var id: String { quarter.rawValue }
    public var quarter: Quarter
    /// Only the categories this app can actually act on. An issuer's quarter
    /// routinely includes things with no place attached — utility bills,
    /// charitable donations, one named retailer's website — and those are in
    /// `summary` instead of being forced into a category that would then make
    /// the app recommend a card at the wrong shop.
    public var categories: [SpendingCategory]
    /// The issuer's own wording, so the app can show what the quarter really is
    /// rather than the subset it understands.
    public var summary: String?
    /// Chase Freedom and Discover it both require a manual click each quarter.
    /// Until this is true the bonus rate does not apply, no matter what you buy.
    public var isActivated: Bool
    public var activationDeadline: Date?
    /// True when the user typed this in because the issuer had not told us yet.
    /// Kept so the UI can say where the number came from, and so a shipped
    /// answer can later replace a guessed one without silently overwriting
    /// something the user checked themselves.
    public var enteredByUser: Bool

    public init(
        quarter: Quarter,
        categories: [SpendingCategory],
        summary: String? = nil,
        isActivated: Bool = false,
        activationDeadline: Date? = nil,
        enteredByUser: Bool = false
    ) {
        self.quarter = quarter
        self.categories = categories
        self.summary = summary
        self.isActivated = isActivated
        self.activationDeadline = activationDeadline
        self.enteredByUser = enteredByUser
    }
}

/// What we know about a given quarter. The middle case is the whole reason this
/// type exists: "no bonus" and "nobody has said yet" look identical in a
/// dictionary lookup and could not be more different to a user about to pay.
public enum RotationStatus: Hashable, Sendable {
    case bonus(RotatingQuarter)
    /// The issuer has published this quarter and it does not apply here.
    case none
    /// Past the end of what anybody has told us. The app must not guess, and
    /// must not stay quiet about it either.
    case unannounced
}

/// The rotating 5% program on cards like Chase Freedom Flex and Discover it.
///
/// **Nothing in here may be invented.** Rotating categories are announced one
/// quarter at a time — Discover publishes a year ahead, Chase about a fortnight
/// before the quarter starts — so a seed database physically cannot know them
/// all, and a plausible-looking guess is worse than a blank: it produces a
/// confident reminder for a bonus that does not exist.
///
/// `knownThrough` is what makes that honest. It records the last quarter the
/// shipped data actually covers. Past it the app says so and asks.
public struct RotatingProgram: Codable, Hashable, Sendable {
    public var rate: Double
    /// Usually $1,500 of spend per quarter.
    public var cap: EarnCap?
    public var quarters: [RotatingQuarter]
    /// The last quarter this data is good for. Nil means nothing is known at
    /// all, which is the correct state for a card added by hand.
    public var knownThrough: Quarter?
    /// The issuer's own page for the current quarter, so the app can send the
    /// user to the only authority that is never out of date.
    public var sourceURL: String?

    public init(
        rate: Double,
        cap: EarnCap? = nil,
        quarters: [RotatingQuarter] = [],
        knownThrough: Quarter? = nil,
        sourceURL: String? = nil
    ) {
        self.rate = rate
        self.cap = cap
        self.quarters = quarters
        self.knownThrough = knownThrough
        self.sourceURL = sourceURL
    }

    public func quarter(_ quarter: Quarter) -> RotatingQuarter? {
        quarters.first { $0.quarter == quarter }
    }

    public func status(for quarter: Quarter) -> RotationStatus {
        if let match = self.quarter(quarter) { return .bonus(match) }
        // Past the forward edge of what anyone has published.
        guard let knownThrough, quarter <= knownThrough else { return .unannounced }
        // Before the first quarter we kept. Chase publishes one quarter at a
        // time and the app does not hoard the old ones, so "we have no record"
        // is the truthful answer here rather than "there was no bonus".
        guard let earliest = quarters.map(\.quarter).min(), quarter >= earliest else {
            return .unannounced
        }
        return .none
    }

    /// The app should ask the user what this quarter is.
    public func needsCategories(asOf date: Date = Date()) -> Bool {
        status(for: Quarter.containing(date)) == .unannounced
    }

    /// Quarters that are current or upcoming and still need a click.
    public func unactivatedQuarters(asOf date: Date = Date()) -> [RotatingQuarter] {
        let current = Quarter.containing(date)
        return quarters
            .filter { !$0.isActivated && $0.quarter >= current }
            .sorted { $0.quarter < $1.quarter }
    }

    /// Replaces a quarter, or adds it. Used both when the user types in what
    /// their issuer emailed them and when a later build ships the real thing.
    public mutating func setQuarter(_ replacement: RotatingQuarter) {
        if let index = quarters.firstIndex(where: { $0.quarter == replacement.quarter }) {
            quarters[index] = replacement
        } else {
            quarters.append(replacement)
            quarters.sort { $0.quarter < $1.quarter }
        }
        if let knownThrough, replacement.quarter > knownThrough {
            self.knownThrough = replacement.quarter
        } else if knownThrough == nil {
            self.knownThrough = replacement.quarter
        }
    }
}
