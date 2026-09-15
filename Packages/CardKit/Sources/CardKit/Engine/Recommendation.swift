import Foundation

/// A rotating bonus sitting switched off that would have won here.
///
/// **It is two facts and not a sentence, because it is read in two places
/// with very different amounts of room.** A card detail screen can afford the
/// whole explanation; a lock screen gets about forty characters before iOS
/// truncates, and the half it throws away is always the end — which is where
/// the rate was. Storing the sentence meant the short place had to cut up the
/// long place's prose, so the pieces live here and each surface writes its
/// own line.
public struct ActivationNudge: Sendable, Hashable {

    /// The card whose bonus is switched off.
    public var cardName: String
    /// What it would pay here, already formatted in the card's own currency —
    /// "5%" or "5x". Never compared against the winner's rate: a percent and
    /// a multiplier are not the same unit.
    public var rateText: String

    public init(cardName: String, rateText: String) {
        self.cardName = cardName
        self.rateText = rateText
    }

    /// For a screen with room to explain itself.
    public var sentence: String {
        "Activate the quarterly bonus on \(cardName). It would pay \(rateText) here."
    }

    /// For a lock screen, where it is the second line at most.
    public var shortSentence: String {
        "Activate \(cardName) for \(rateText)."
    }
}

/// The finished answer. The notification shows `headline` and `detail` and
/// names exactly one card; everything else appears only after a tap.
public struct Recommendation: Sendable, Hashable {
    public var best: CardScore
    public var alternates: [CardScore]
    public var headline: String
    public var detail: String
    /// Set when a rotating bonus the user has not activated would have won.
    public var activationNudge: ActivationNudge?
    public var travelPerkSummary: String?

    public var caveats: [String] { best.caveats }

    /// What the next best card in the wallet would have paid here.
    ///
    /// **This exists to stop a screen saying the same thing twice.** A
    /// recommendation surface naturally wants three lines, and the engine
    /// naturally supplies three that overlap: `headline` is "Use Amex Gold
    /// here", `rewardLine` is "4x points with American Express Gold", and
    /// `best.reason` is "4x dining". Stack them and the reader is told the
    /// card twice and the rate twice, and the third line has earned nothing.
    ///
    /// The fact genuinely missing is the comparison the ranking just made and
    /// then discarded. 4x is worth crossing a room for only if the card you
    /// would otherwise have reached for pays less, and *how much* less is the
    /// whole size of the decision. It is also the same quantity the impact
    /// ledger reports — see the note on incremental value in CLAUDE.md — so
    /// the app is consistent about what it thinks a reminder is worth.
    ///
    /// **Nil rather than a sentence, three times over.** A wallet of one card
    /// has no runner-up; a runner-up at the same rate is not a comparison; and
    /// there is no filler to write for either. A screen reading this draws
    /// nothing rather than something true but empty.
    public var runnerUpLine: String? {
        guard let runnerUp = alternates.first else { return nil }
        let theirs = runnerUp.card.currency.formatted(rate: runnerUp.appliedRate)
        let ours = best.card.currency.formatted(rate: best.appliedRate)
        guard theirs != ours else { return nil }
        return "Your next best card here is \(runnerUp.card.displayName), at \(theirs)."
    }
}
