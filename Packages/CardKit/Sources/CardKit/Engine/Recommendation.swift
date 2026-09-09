import Foundation

/// The finished answer. The notification shows `headline` and `detail` and
/// names exactly one card; everything else appears only after a tap.
public struct Recommendation: Sendable, Hashable {
    public var best: CardScore
    public var alternates: [CardScore]
    public var headline: String
    public var detail: String
    /// Set when a rotating bonus the user has not activated would have won.
    public var activationNudge: String?
    public var travelPerkSummary: String?

    public var caveats: [String] { best.caveats }
}
