import Foundation

/// Somebody has crossed into a geofence and we are waiting to see whether they
/// stay. Nothing is shown to the user until `confirmAt` passes.
public struct PendingArrival: Identifiable, Codable, Hashable, Sendable {
    public var id: String { regionID }
    public var regionID: String
    public var merchant: Merchant
    public var enteredAt: Date
    public var confirmAt: Date

    public init(regionID: String, merchant: Merchant, enteredAt: Date, confirmAt: Date) {
        self.regionID = regionID
        self.merchant = merchant
        self.enteredAt = enteredAt
        self.confirmAt = confirmAt
    }

    public func isDue(asOf date: Date, tolerance: TimeInterval = 0) -> Bool {
        date.timeIntervalSince(confirmAt) >= -tolerance
    }

    public func secondsRemaining(asOf date: Date) -> TimeInterval {
        max(0, confirmAt.timeIntervalSince(date))
    }
}

/// The dwell rule: entering is not arriving.
///
/// A geofence entry fires when you walk past a shop, sit at a red light outside
/// it, or cut through its car park. Those are not purchases, and a notification
/// for each of them is how an app gets its notifications turned off in a week.
/// So an entry starts a clock instead of a notification, and leaving before the
/// clock runs out cancels it silently.
///
/// Three to five minutes is the window: long enough to have walked in, queued,
/// and be somewhere near a till; short enough to still beat the card out of the
/// wallet. Four is the default.
///
/// Pure value type with an injected clock — every rule below is a unit test,
/// which matters because the real thing cannot be exercised without walking
/// around a city with a phone.
public struct ArrivalTracker: Codable, Hashable, Sendable {

    public static let minimumConfirmationDelay: TimeInterval = 3 * 60
    public static let maximumConfirmationDelay: TimeInterval = 5 * 60

    /// Clamped into the 3-5 minute window on the way in, so no caller can
    /// accidentally set it to zero and turn this back into a drive-by notifier.
    public private(set) var confirmationDelay: TimeInterval
    /// A scheduled notification can fire a moment early. Treating that as "not
    /// due yet" would drop the arrival entirely.
    public var confirmationTolerance: TimeInterval
    /// An entry with no matching exit — phone off, region forgotten, user drove
    /// out of range faster than iOS noticed — should not sit pending forever.
    public var maximumPendingAge: TimeInterval

    public private(set) var pending: [PendingArrival]

    public init(
        confirmationDelay: TimeInterval = 4 * 60,
        confirmationTolerance: TimeInterval = 5,
        maximumPendingAge: TimeInterval = 60 * 60,
        pending: [PendingArrival] = []
    ) {
        self.confirmationDelay = min(
            max(confirmationDelay, Self.minimumConfirmationDelay),
            Self.maximumConfirmationDelay
        )
        self.confirmationTolerance = confirmationTolerance
        self.maximumPendingAge = maximumPendingAge
        self.pending = pending
    }

    // MARK: - Events

    /// A `didEnterRegion`. Returns the arrival to schedule, or nothing when this
    /// region is already pending — iOS will happily deliver the same entry twice
    /// as the fix wobbles across the boundary, and each one must not restart or
    /// duplicate the clock.
    @discardableResult
    public mutating func enter(_ region: MonitoredRegion, at date: Date) -> PendingArrival? {
        guard !pending.contains(where: { $0.regionID == region.id }) else { return nil }
        let arrival = PendingArrival(
            regionID: region.id,
            merchant: region.merchant,
            enteredAt: date,
            confirmAt: date.addingTimeInterval(confirmationDelay)
        )
        pending.append(arrival)
        return arrival
    }

    /// A `didExitRegion`. Returns the arrival that was cancelled, so the caller
    /// knows to unschedule it. Exiting a region we were not waiting on is a
    /// no-op, which happens routinely: iOS reports exits for regions whose
    /// entry we never saw.
    @discardableResult
    public mutating func exit(regionID: String, at date: Date) -> PendingArrival? {
        guard let index = pending.firstIndex(where: { $0.regionID == regionID }) else { return nil }
        return pending.remove(at: index)
    }

    /// The clock ran out. Returns the arrival to notify about, or nothing if it
    /// was cancelled in the meantime or is not due yet.
    public mutating func confirm(regionID: String, at date: Date) -> PendingArrival? {
        guard let index = pending.firstIndex(where: { $0.regionID == regionID }) else { return nil }
        guard pending[index].isDue(asOf: date, tolerance: confirmationTolerance) else { return nil }
        return pending.remove(at: index)
    }

    /// Everything whose clock has run out, oldest first. The app calls this
    /// whenever it wakes, so an arrival still gets through on the occasions the
    /// scheduled notification did not.
    public mutating func confirmDue(asOf date: Date) -> [PendingArrival] {
        let due = pending
            .filter { $0.isDue(asOf: date, tolerance: confirmationTolerance) }
            .sorted { $0.confirmAt < $1.confirmAt }
        let dueIDs = Set(due.map(\.regionID))
        pending.removeAll { dueIDs.contains($0.regionID) }
        return due
    }

    /// Drops arrivals that have outlived their usefulness. Returns them so the
    /// caller can unschedule whatever it scheduled for them.
    @discardableResult
    public mutating func purgeStale(asOf date: Date) -> [PendingArrival] {
        let stale = pending.filter { date.timeIntervalSince($0.enteredAt) > maximumPendingAge }
        let staleIDs = Set(stale.map(\.regionID))
        pending.removeAll { staleIDs.contains($0.regionID) }
        return stale
    }

    /// Forgets everything, and hands back what it forgot. Used when the plan is
    /// rebuilt: a pending arrival for a region we no longer monitor can never
    /// receive its exit, so it would hang until it went stale.
    @discardableResult
    public mutating func dropArrivals(outside regionIDs: Set<String>) -> [PendingArrival] {
        let dropped = pending.filter { !regionIDs.contains($0.regionID) }
        pending.removeAll { !regionIDs.contains($0.regionID) }
        return dropped
    }

    public func arrival(forRegionID id: String) -> PendingArrival? {
        pending.first { $0.regionID == id }
    }
}
