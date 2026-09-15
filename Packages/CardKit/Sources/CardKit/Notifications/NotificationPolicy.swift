import Foundation

/// Everything the app is allowed to believe about when to interrupt somebody.
///
/// **One struct, and nothing outside it may hold an opinion.** Before this,
/// "how chatty is CardWise" was answered in four places — a daily ceiling on
/// `ReminderThrottle`, a minimum edge on `RecommendationEngine`, a dwell on
/// `ArrivalTracker`, and an implicit "always send it" in `RegionMonitor`.
/// Tuning the product meant finding all four and hoping there was not a fifth.
///
/// **It works well with nobody having configured anything.** Every field has a
/// default that is the right answer for somebody who installed the app ten
/// minutes ago and will never open Settings. The settings screen exists for
/// refinement, not for setup — an app that needs to be configured before it
/// behaves reasonably has shipped its homework.
public struct NotificationPolicy: Codable, Hashable, Sendable {

    /// How much the user wants to hear. Everything numeric comes from here.
    public var intensity: NotificationIntensity

    public var quietHours: QuietHours

    /// Categories the user has switched off entirely. Empty by default: the
    /// app guesses which categories are worth watching from the wallet, and a
    /// category nobody's card pays a bonus on never gets a geofence in the
    /// first place.
    public var disabledCategories: Set<SpendingCategory>

    /// Shops that have been muted, and until when. `Date.distantFuture` is
    /// "always".
    ///
    /// **A place identifier, stored on purpose and kept to a minimum.** This
    /// is the one structure in the notification layer that names a specific
    /// place. It holds an opaque provider id and an expiry — no name, no
    /// coordinate, no visit, no timestamp of having been there — and entries
    /// expire themselves. Muting your own office coffee shop is not worth
    /// building a location history for.
    public var mutedMerchants: [String: Date]

    public init(
        intensity: NotificationIntensity = .default,
        quietHours: QuietHours = .standard,
        disabledCategories: Set<SpendingCategory> = [],
        mutedMerchants: [String: Date] = [:]
    ) {
        self.intensity = intensity
        self.quietHours = quietHours
        self.disabledCategories = disabledCategories
        self.mutedMerchants = mutedMerchants
    }

    public var thresholds: NotificationThresholds { intensity.thresholds }

    // MARK: - Categories

    public func allows(category: SpendingCategory) -> Bool {
        !disabledCategories.contains(category)
    }

    public mutating func setCategory(_ category: SpendingCategory, enabled: Bool) {
        if enabled {
            disabledCategories.remove(category)
        } else {
            disabledCategories.insert(category)
        }
    }

    // MARK: - Muting a shop

    /// How long a mute lasts. Three options and no free-form date picker:
    /// somebody tapping "not this place" on a lock screen is not filling in a
    /// form.
    public enum MuteDuration: String, CaseIterable, Sendable, Hashable {
        case today
        case week
        case always

        public var displayName: String {
            switch self {
            case .today: return "Mute for today"
            case .week: return "Mute for a week"
            case .always: return "Always mute"
            }
        }

        public func expiry(from date: Date, calendar: Calendar = .current) -> Date {
            switch self {
            case .today:
                let tomorrow = calendar.date(byAdding: .day, value: 1, to: date) ?? date
                return calendar.startOfDay(for: tomorrow)
            case .week:
                return calendar.date(byAdding: .day, value: 7, to: date) ?? date
            case .always:
                return .distantFuture
            }
        }
    }

    public func isMuted(merchantID: String, at date: Date) -> Bool {
        guard let until = mutedMerchants[merchantID] else { return false }
        return until > date
    }

    public mutating func mute(
        merchantID: String,
        for duration: MuteDuration,
        from date: Date = Date(),
        calendar: Calendar = .current
    ) {
        mutedMerchants[merchantID] = duration.expiry(from: date, calendar: calendar)
    }

    public mutating func unmute(merchantID: String) {
        mutedMerchants.removeValue(forKey: merchantID)
    }

    /// Drops mutes that have run out. Called whenever the policy is written,
    /// so a dictionary that rides along in a saved file cannot grow across a
    /// year of tapping "mute for today".
    public mutating func pruneExpiredMutes(asOf date: Date = Date()) {
        mutedMerchants = mutedMerchants.filter { $0.value > date }
    }
}
