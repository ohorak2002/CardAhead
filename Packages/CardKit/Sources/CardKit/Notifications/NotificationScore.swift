import Foundation

/// One line of the arithmetic, kept so the total can explain itself.
///
/// **A score nobody can take apart cannot be tuned.** "74" is unarguable and
/// useless; "+30 card advantage, +18 value, +12 choice, +10 confidence, −6
/// already sent one today" is a thing somebody can look at and say *that
/// weight is wrong*. The debug screen prints these, and so does a failing
/// test.
public struct ScoreComponent: Codable, Hashable, Sendable {

    /// "Card advantage". Short enough for a row.
    public var label: String
    /// Signed. Negatives are the reasons to stay quiet.
    public var points: Double
    /// "4x versus 1x" — the measurement behind the points, when there is one
    /// worth showing.
    public var detail: String?

    public init(label: String, points: Double, detail: String? = nil) {
        self.label = label
        self.points = points
        self.detail = detail
    }
}

/// The finished arithmetic.
public struct NotificationScore: Codable, Hashable, Sendable {

    public var components: [ScoreComponent]

    public init(components: [ScoreComponent] = []) {
        self.components = components
    }

    /// Clamped to 0...100, because the bands are expressed in those terms and
    /// a score of 130 would put `NotificationBand.containing` in a range it
    /// was never designed for.
    public var total: Double {
        min(100, max(0, components.reduce(0) { $0 + $1.points }))
    }

    /// Before clamping — what the components actually add up to. Useful when
    /// tuning, because a run of candidates all pinned at 100 says the weights
    /// are too generous and the clamped total hides that.
    public var rawTotal: Double {
        components.reduce(0) { $0 + $1.points }
    }

    public var band: NotificationBand { .containing(total) }

    /// 0...1, for `UNNotificationContent.relevanceScore`, which iOS uses to
    /// decide what floats to the top of a notification summary.
    ///
    /// **Not a probability and not machine learning.** It is the same
    /// deterministic total divided by a hundred, and saying so here is the
    /// point — `relevanceScore` is the kind of API that invites a made-up
    /// confidence value.
    public var relevance: Double { total / 100 }

    public var positives: [ScoreComponent] { components.filter { $0.points > 0 } }
    public var negatives: [ScoreComponent] { components.filter { $0.points < 0 } }

    mutating func add(_ label: String, _ points: Double, _ detail: String? = nil) {
        guard points != 0 else { return }
        components.append(ScoreComponent(label: label, points: points, detail: detail))
    }
}
