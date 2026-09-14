import Foundation

/// Where events go when they go anywhere.
///
/// **Today they go nowhere.** The app installs `NoOpAnalyticsService`: there is
/// no backend, no account, no network call, and the only record of anything is
/// the `ImpactLedger` file on the phone, which the user can erase from
/// Settings. This protocol is one screen's worth of code, and it exists for a
/// single reason — so that adding a backend later is one new type conforming
/// here, instead of a change to every screen that does something worth
/// counting. A seam is cheap now and expensive to retrofit.
///
/// If anything ever does implement this over a network, two rules are already
/// written down and already tested:
///
/// - It receives `ImpactEvent.redactedForAnalytics()`, never the raw event.
///   No wallet card ids, no card names, and — by construction of the event
///   itself — no merchant, no coordinate, no payment credential of any kind.
/// - It is off unless the user turned it on. Nothing about measuring whether
///   this app is useful requires anybody's financial account.
public protocol AnalyticsService: AnyObject, Sendable {
    func record(_ event: ImpactEvent)
}

/// What ships. Takes the event and drops it.
public final class NoOpAnalyticsService: AnalyticsService {
    public init() {}
    public func record(_ event: ImpactEvent) {}
}

/// Keeps what it is given, so a test can assert on what a screen emitted and
/// on what redaction actually removed.
public final class RecordingAnalyticsService: AnalyticsService, @unchecked Sendable {

    private let lock = NSLock()
    private var storage: [ImpactEvent] = []

    public init() {}

    public var events: [ImpactEvent] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    public func record(_ event: ImpactEvent) {
        lock.lock()
        storage.append(event)
        lock.unlock()
    }
}
