import Foundation
import os
import CardKit

/// Whatever is going to tell the user, once an arrival has held for its few
/// minutes.
///
/// A protocol rather than a direct call because the wait has to be handed to
/// something that outlives the process: the app is usually suspended for the
/// whole of those four minutes, so nothing it holds in memory can be relied on
/// to still be there when they are up. See `ReminderCenter`.
protocol ArrivalNotifier: AnyObject {
    /// Called the moment a geofence is entered, and again whenever the wallet
    /// changes while an arrival is still in its dwell window — see
    /// `RegionMonitor.walletDidChange()`. The implementation is responsible
    /// for surfacing the arrival at `arrival.confirmAt` and not before.
    ///
    /// Returns the frozen numbers behind whatever was scheduled, or the reason
    /// nothing was. `.stayQuiet` means there was nothing worth saying — an
    /// empty wallet, no bonus here, a cap already spent — and the caller must
    /// not count that against any frequency limit it is tracking, because
    /// nothing is going to arrive.
    ///
    /// The snapshot comes back rather than staying inside because the caller
    /// is what remembers arrivals across a launch: pricing a suggestion later
    /// needs the numbers as they were at the till, and by then the wallet has
    /// moved on. See `RecommendationSnapshot`.
    @discardableResult
    func schedule(_ arrival: PendingArrival) -> ArrivalDecision

    /// The user left before the clock ran out, or the region was dropped from
    /// the plan. Nothing should reach them.
    func cancel(regionID: String)
}

/// Writes the arrival to the log and does nothing else.
///
/// `ReminderCenter` is what the app installs. This is the default only so that
/// a `RegionMonitor` built for a SwiftUI preview cannot put a real notification
/// on somebody's lock screen. It reports `.stayQuiet` because nothing was
/// scheduled and nothing will arrive — a preview must not spend a real day's
/// reminder allowance or leave a question in the ledger nobody can answer.
final class LoggingArrivalNotifier: ArrivalNotifier {

    private let log = Logger(subsystem: AppLog.subsystem, category: "arrivals")

    @discardableResult
    func schedule(_ arrival: PendingArrival) -> ArrivalDecision {
        log.notice("""
            would schedule \(arrival.regionID, privacy: .public) \
            confirm in \(Int(arrival.confirmAt.timeIntervalSince(arrival.enteredAt)), privacy: .public)s
            """)
        return .stayQuiet(.noCards)
    }

    func cancel(regionID: String) {
        log.notice("cancelled \(regionID, privacy: .public)")
    }
}

enum AppLog {
    static let subsystem = Bundle.main.bundleIdentifier ?? "com.ohorak.cardrewards"
}
