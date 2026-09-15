import Foundation

/// How much the user wants to hear from CardWise.
///
/// **Four settings, and every one of them is the same architecture.** The
/// temptation with a "notification frequency" control is to give each level
/// its own behaviour — minimal skips the budget, frequent skips the
/// cooldowns — and the result is four products, three of which nobody tests.
/// These are four sets of *numbers* fed to one decision engine. A bug found
/// at Balanced is a bug fixed at all four.
public enum NotificationIntensity: String, Codable, CaseIterable, Sendable, Hashable {

    /// Only the unusually valuable.
    case minimal
    /// Meaningful recommendations, where the app can genuinely help. The
    /// default, and the only one most people should ever need.
    case balanced
    /// More of them, including moderate opportunities.
    case helpful
    /// Most things that qualify at all.
    case frequent

    public static let `default`: NotificationIntensity = .balanced

    public var displayName: String {
        switch self {
        case .minimal: return "Minimal"
        case .balanced: return "Balanced"
        case .helpful: return "Helpful"
        case .frequent: return "Frequent"
        }
    }

    /// Said in terms of what will actually happen, not in adjectives. Somebody
    /// picking a row wants to know how many notifications they are agreeing
    /// to, and "Helpful" on its own does not say.
    public var explanation: String {
        switch self {
        case .minimal:
            return "Only when a card is worth a lot more than the rest. About one a day at most."
        case .balanced:
            return "When CardWise can genuinely help you choose. Up to three a day."
        case .helpful:
            return "Smaller wins too, and sooner after the last one. Up to five a day."
        case .frequent:
            return "Nearly anything that qualifies. Up to eight a day."
        }
    }

    public var thresholds: NotificationThresholds {
        switch self {
        case .minimal:
            return NotificationThresholds(
                dailyBudget: 1,
                minimumScore: 82,
                merchantCooldownHours: 72,
                categoryCooldownHours: 12,
                overrideValueCents: 1_200
            )
        case .balanced:
            return NotificationThresholds(
                dailyBudget: 3,
                minimumScore: 58,
                merchantCooldownHours: 24,
                categoryCooldownHours: 4,
                overrideValueCents: 500
            )
        case .helpful:
            return NotificationThresholds(
                dailyBudget: 5,
                minimumScore: 45,
                merchantCooldownHours: 12,
                categoryCooldownHours: 2,
                overrideValueCents: 350
            )
        case .frequent:
            return NotificationThresholds(
                dailyBudget: 8,
                minimumScore: 32,
                merchantCooldownHours: 6,
                categoryCooldownHours: 1,
                overrideValueCents: 200
            )
        }
    }
}

/// Every number the decision engine is allowed to compare against, in one
/// place.
///
/// **This type exists so that no threshold is ever written at a call site.**
/// The old shape of this problem — `maxPerDay: 5` on the throttle,
/// `minimumArrivalEdgeCentsPerDollar` on the ranking engine, a four-minute
/// dwell in the tracker — meant that "how chatty is this app" was a question
/// with no single answer and four places to go and look. Tuning it meant
/// finding all four. Now there is one struct, and `NotificationIntensity`
/// picks which instance of it is in force.
public struct NotificationThresholds: Codable, Hashable, Sendable {

    /// Ordinary reminders allowed in one calendar day. Exceptional ones can
    /// still get through — see `overrideValueCents`.
    public var dailyBudget: Int

    /// The score, out of 100, below which nothing is sent. See
    /// `NotificationBand` for what the numbers mean.
    public var minimumScore: Double

    /// How long the same shop is left alone after a reminder about it.
    public var merchantCooldownHours: Double

    /// And the same *kind* of shop. Shorter than the merchant cooldown on
    /// purpose: two different restaurants in an afternoon is a plausible day
    /// out, two reminders about the same restaurant is a malfunction.
    public var categoryCooldownHours: Double

    /// What an opportunity has to be worth, in cents, to be sent anyway once
    /// the day's budget is spent.
    ///
    /// **The case this exists for.** Somebody gets three reminders worth about
    /// fifteen cents, a dollar and fifty cents, then walks into a hotel where
    /// the right card is worth twenty dollars. A budget with no override
    /// spends the whole day on the coffee and stays silent for the hotel,
    /// which is precisely backwards.
    public var overrideValueCents: Double

    public init(
        dailyBudget: Int,
        minimumScore: Double,
        merchantCooldownHours: Double,
        categoryCooldownHours: Double,
        overrideValueCents: Double
    ) {
        self.dailyBudget = dailyBudget
        self.minimumScore = minimumScore
        self.merchantCooldownHours = merchantCooldownHours
        self.categoryCooldownHours = categoryCooldownHours
        self.overrideValueCents = overrideValueCents
    }

    public var merchantCooldown: TimeInterval { merchantCooldownHours * 3_600 }
    public var categoryCooldown: TimeInterval { categoryCooldownHours * 3_600 }
}

/// What a score means.
///
/// **Starting points, not product truth.** These four bands are the thing most
/// likely to be wrong on the first real week of use, which is exactly why they
/// are four numbers in one enum rather than a chain of `if` statements spread
/// through the engine.
public enum NotificationBand: String, Codable, CaseIterable, Sendable, Hashable {

    /// Not worth an interruption at all.
    case suppress
    /// Worth having in Notification Centre, not worth a sound or a banner.
    case passive
    /// An ordinary, useful reminder.
    case normal
    /// Unusually valuable. Still not Time Sensitive — see
    /// `NotificationInterruption`.
    case high

    public static func containing(_ score: Double) -> NotificationBand {
        switch score {
        case ..<30: return .suppress
        case ..<60: return .passive
        case ..<80: return .normal
        default: return .high
        }
    }

    public var displayName: String {
        switch self {
        case .suppress: return "Suppress"
        case .passive: return "Passive"
        case .normal: return "Normal"
        case .high: return "High priority"
        }
    }
}

/// How loudly iOS should deliver something.
///
/// A CardKit mirror of `UNNotificationInterruptionLevel`, because CardKit does
/// not import UserNotifications — the whole point of the package is that the
/// policy is testable on Linux. The app maps this onto the real thing.
///
/// **There is deliberately no `timeSensitive` and no `critical` case.** Apple
/// reserves Time Sensitive for things that need attention *now*, and a
/// restaurant recommendation is useful without being urgent; using it to win
/// attention is how an app gets its notifications turned off by somebody who
/// felt tricked. If a genuinely time-dependent case ever appears — a credit
/// that expires tonight, at the shop it applies to — this enum is where it
/// would be added, with the argument written down next to it.
public enum NotificationInterruption: String, Codable, CaseIterable, Sendable, Hashable {
    /// No sound, no banner. It waits in Notification Centre.
    case passive
    /// The normal one: a banner and the default sound.
    case active
}
