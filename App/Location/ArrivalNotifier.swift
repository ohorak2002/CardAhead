import Foundation
import os
import CardKit

/// Whatever is going to tell the user, once an arrival has held for its few
/// minutes.
///
/// A protocol rather than a direct call because the two halves land in separate
/// steps: region monitoring first, notifications after. It is also the only
/// seam at which the delay can be implemented properly — the app is usually
/// suspended for the whole of those four minutes, so the wait has to be handed
/// to something that outlives the process.
protocol ArrivalNotifier: AnyObject {
    /// Called the moment a geofence is entered. The implementation is
    /// responsible for surfacing the arrival at `arrival.confirmAt` and not
    /// before.
    func schedule(_ arrival: PendingArrival)

    /// The user left before the clock ran out, or the region was dropped from
    /// the plan. Nothing should reach them.
    func cancel(regionID: String)
}

/// Writes the arrival to the log and does nothing else.
///
/// This is what is installed until `UNUserNotificationCenter` is wired up. It
/// is not a stub in the sense of pretending: the arrival really is tracked, the
/// clock really does run, and `RegionMonitor` really does confirm it whenever
/// the app is awake at the time. The only missing piece is the part that
/// interrupts the user, which is deliberately a separate change.
final class LoggingArrivalNotifier: ArrivalNotifier {

    private let log = Logger(subsystem: AppLog.subsystem, category: "arrivals")

    func schedule(_ arrival: PendingArrival) {
        log.notice("""
            scheduled \(arrival.regionID, privacy: .public) \
            confirm in \(Int(arrival.confirmAt.timeIntervalSince(arrival.enteredAt)), privacy: .public)s
            """)
    }

    func cancel(regionID: String) {
        log.notice("cancelled \(regionID, privacy: .public)")
    }
}

enum AppLog {
    static let subsystem = Bundle.main.bundleIdentifier ?? "com.example.cardrewards"
}
