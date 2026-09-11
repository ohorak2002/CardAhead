import Foundation
import Observation
import os
import UIKit
import UserNotifications
import CardKit

/// Owns the second permission, and the only thing the user ever sees this app
/// do while it is closed.
///
/// It implements `ArrivalNotifier`, so `RegionMonitor` hands it an arrival the
/// instant a geofence is crossed and never learns how the waiting is done.
/// The waiting is done by iOS: the notification is scheduled four minutes out
/// with a `UNTimeIntervalNotificationTrigger` and cancelled if an exit arrives
/// first. That is the only mechanism that survives the app being suspended for
/// the whole of those four minutes, which it invariably is.
///
/// The consequence, and it is deliberate: **the sentence is written on the way
/// in, not on the way out.** At the moment it fires there is no process to
/// write it. So a card deleted during the wait can still be named on the lock
/// screen; tapping through lands on the wallet instead of a card that is gone.
@Observable
final class ReminderCenter: NSObject, UNUserNotificationCenterDelegate, ArrivalNotifier {

    /// Identifier under which the card is carried through the notification.
    static let cardIDKey = "cardID"
    private static let threadIdentifier = "arrivals"

    private(set) var status: UNAuthorizationStatus = .notDetermined
    /// Set when somebody taps a reminder. The wallet screen consumes it and
    /// puts it back to nil.
    var cardToOpen: UUID?

    @ObservationIgnored var walletCards: () -> [Card] = { [] }

    private let center = UNUserNotificationCenter.current()
    private let engine = RecommendationEngine()
    private let log = Logger(subsystem: AppLog.subsystem, category: "reminders")

    override init() {
        super.init()
        // Set during launch, not on first use: a tap on a reminder is what
        // launches the app, and the delegate has to exist to receive it.
        center.delegate = self
    }

    // MARK: - Permission

    var isAuthorized: Bool {
        status == .authorized || status == .provisional || status == .ephemeral
    }

    /// iOS has already asked and been told no. Only Settings can change it now.
    var isBlocked: Bool { status == .denied }

    var canStillAsk: Bool { status == .notDetermined }

    @MainActor
    func refreshStatus() async {
        status = await center.notificationSettings().authorizationStatus
    }

    /// Never called on launch. The ask only makes sense once the user has
    /// agreed to be located, because until then there is nothing to notify
    /// them about — see `LocationPrimerView`.
    @MainActor
    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            await refreshStatus()
            return granted
        } catch {
            log.error("notification authorization failed: \(error.localizedDescription, privacy: .public)")
            await refreshStatus()
            return false
        }
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString),
              UIApplication.shared.canOpenURL(url)
        else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - ArrivalNotifier

    /// Writes the notification and hands it to iOS with a delayed trigger, or
    /// clears whatever was there before if there is nothing left to say.
    ///
    /// Called again, with the same `arrival.regionID`, whenever the wallet
    /// changes while this arrival is still dwelling — `center.add` replaces a
    /// pending request under the same identifier rather than stacking a
    /// second one, so re-rendering here is exactly how a card deleted or
    /// corrected mid-wait stops being named on the lock screen four minutes
    /// later. The cancel below is what makes that work when the *new* answer
    /// is silence: the first call had nothing to cancel, but a refresh does.
    @discardableResult
    func schedule(_ arrival: PendingArrival) -> Bool {
        guard let reminder = engine.reminder(
            for: arrival,
            cards: walletCards(),
            asOf: arrival.confirmAt
        ) else {
            log.notice("nothing worth saying about \(arrival.regionID, privacy: .public)")
            cancel(regionID: arrival.regionID)
            return false
        }

        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.sound = .default
        content.threadIdentifier = Self.threadIdentifier
        content.userInfo = [Self.cardIDKey: reminder.cardID.uuidString]

        // A trigger of zero is rejected, and an entry whose clock somehow
        // already ran out should still be shown rather than dropped.
        let delay = max(1, arrival.confirmAt.timeIntervalSinceNow)
        let request = UNNotificationRequest(
            identifier: arrival.regionID,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        )

        center.add(request) { [weak self] error in
            guard let error else { return }
            self?.log.error("could not schedule \(request.identifier, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
        return true
    }

    func cancel(regionID: String) {
        center.removePendingNotificationRequests(withIdentifiers: [regionID])
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Shown even with the app open. Somebody who has the app in front of them
    /// at the moment they walk in is exactly who the reminder is for.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }
        guard let raw = response.notification.request.content.userInfo[Self.cardIDKey] as? String,
              let id = UUID(uuidString: raw)
        else { return }
        cardToOpen = id
        log.notice("reminder tapped, opening a card")
    }
}
