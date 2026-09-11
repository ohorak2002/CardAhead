import Foundation

/// One notification that actually got scheduled, kept just long enough to
/// enforce today's limits against it.
public struct FiredReminder: Codable, Hashable, Sendable {
    public var merchantID: String
    public var firedAt: Date

    public init(merchantID: String, firedAt: Date) {
        self.merchantID = merchantID
        self.firedAt = firedAt
    }
}

/// The rules for whether an arrival that has something worth saying actually
/// gets to say it.
///
/// A confirmed dwell is necessary but not sufficient. The regular grocery run
/// would otherwise notify every single week forever, and a day with six short
/// errands would notify six times before lunch — which is how an app earns
/// its notifications being switched off. Two independent limits: at most a
/// handful a day regardless of where, and at most one per shop per day no
/// matter how many times you walk past it.
///
/// **Where "fired" is decided, and the one imprecision that comes with it.**
/// A reminder is scheduled at the moment of *entry*, four minutes before it
/// would actually reach the lock screen — see `ReminderCenter`'s own note on
/// why the content has to be written then and not at delivery. There is no
/// code that runs at the actual moment of delivery to record a limit against,
/// only at entry and (if the app is later reopened) at confirmation. So a
/// reminder is counted as "fired" the moment it is scheduled, not the moment
/// it is delivered. The one case this gets slightly wrong: someone walks in,
/// a reminder is scheduled and counted, and they leave again inside a minute
/// — the notification never arrives, but the day's count and that shop's
/// dedup are both already spent. Rare, and the alternative (waiting for a
/// confirmation that may never run while the app is asleep) would let a
/// determined re-entry blow through the daily ceiling instead.
public struct ReminderThrottle: Codable, Hashable, Sendable {

    /// Every reminder scheduled recently, oldest first. Pruned on every write
    /// so a throttle that rides along in a file saved on every arrival cannot
    /// grow across a year of use.
    public private(set) var fired: [FiredReminder]

    /// How many reminders about the *same* shop are allowed in one day.
    public var maxPerMerchantPerDay: Int
    /// How many reminders in total, regardless of shop, are allowed in one day.
    public var maxPerDay: Int

    public init(
        fired: [FiredReminder] = [],
        maxPerMerchantPerDay: Int = 1,
        maxPerDay: Int = 5
    ) {
        self.fired = fired
        self.maxPerMerchantPerDay = maxPerMerchantPerDay
        self.maxPerDay = maxPerDay
    }

    /// Whether a reminder about this merchant, right now, is allowed to go
    /// out. Read-only — deciding to send one is `recordFired`'s job, kept
    /// separate so a caller can check without committing to anything.
    public func allows(merchantID: String, at date: Date, calendar: Calendar = .current) -> Bool {
        let today = fired.filter { calendar.isDate($0.firedAt, inSameDayAs: date) }
        guard today.count < maxPerDay else { return false }
        let atThisMerchant = today.filter { $0.merchantID == merchantID }
        return atThisMerchant.count < maxPerMerchantPerDay
    }

    /// Call once a reminder has actually been handed to the notification
    /// centre — never speculatively, and never for one `allows` refused.
    ///
    /// Also prunes anything more than two days old. Two, not one, because a
    /// reminder scheduled at 11:58pm and checked again just after midnight
    /// must still count against the day it was scheduled on.
    public mutating func recordFired(merchantID: String, at date: Date, calendar: Calendar = .current) {
        fired.append(FiredReminder(merchantID: merchantID, firedAt: date))
        let cutoff = calendar.date(byAdding: .day, value: -2, to: date) ?? date
        fired.removeAll { $0.firedAt < cutoff }
    }
}
