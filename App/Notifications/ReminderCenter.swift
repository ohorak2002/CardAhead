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
    /// And the suggestion itself, so a tap can be counted against the one it
    /// was a tap on. See `ImpactLedger`.
    static let recommendationIDKey = "recommendationID"
    private static let threadIdentifier = "arrivals"

    /// The category the actions hang off. Registered once at launch —
    /// `UNNotificationCategory` is matched by string at delivery time, so a
    /// notification whose category was never registered simply arrives with
    /// no actions and no error.
    static let arrivalCategoryIdentifier = "arrival"

    /// Told when somebody answers one of the actions on the notification
    /// itself. A closure for the same reason `walletCards` is one.
    @ObservationIgnored var onFeedback: (UUID, NotificationFeedback) -> Void = { _, _ in }

    private(set) var status: UNAuthorizationStatus = .notDetermined
    /// Set when somebody taps a reminder. The wallet screen consumes it and
    /// puts it back to nil.
    var cardToOpen: UUID?

    @ObservationIgnored var walletCards: () -> [Card] = { [] }

    /// Told when somebody taps a reminder, with the suggestion they tapped.
    /// A closure rather than a reference to the impact store for the same
    /// reason `walletCards` is one: this class owns notifications, and what
    /// anybody else does about them is not its business.
    @ObservationIgnored var onOpened: (UUID) -> Void = { _ in }

    private let center = UNUserNotificationCenter.current()
    private let engine = RecommendationEngine()
    private let log = Logger(subsystem: AppLog.subsystem, category: "reminders")

    override init() {
        super.init()
        // Set during launch, not on first use: a tap on a reminder is what
        // launches the app, and the delegate has to exist to receive it.
        center.delegate = self
        registerActions()
    }

    /// The buttons under a reminder.
    ///
    /// **Two, not four.** "Used it" and "Not here" are the two answers worth
    /// having from a lock screen: one says the advice landed, the other says
    /// the *detection* was wrong, and they are different bugs with different
    /// fixes. "Not useful" is a preference, not a moment — it belongs in
    /// Settings next to the category switches, where somebody can see what
    /// they are turning off. A lock screen with four buttons on it is a form.
    ///
    /// Neither is destructive and neither needs the app open: both are
    /// `.authenticationRequired` off and handled in the background, so
    /// answering costs a tap and not a launch.
    private func registerActions() {
        let usedIt = UNNotificationAction(
            identifier: NotificationFeedback.usedIt.rawValue,
            title: NotificationFeedback.usedIt.displayName,
            options: []
        )
        let notHere = UNNotificationAction(
            identifier: NotificationFeedback.notHere.rawValue,
            title: NotificationFeedback.notHere.displayName,
            options: []
        )
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: Self.arrivalCategoryIdentifier,
                actions: [usedIt, notHere],
                intentIdentifiers: [],
                options: []
            )
        ])
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
    func schedule(_ arrival: PendingArrival, decision: NotificationDecision? = nil) -> ArrivalDecision {
        let decision = engine.decide(
            for: arrival,
            cards: walletCards(),
            asOf: arrival.confirmAt
        )
        guard case .send(let reminder, let snapshot) = decision else {
            log.notice("nothing worth saying about \(arrival.regionID, privacy: .public)")
            cancel(regionID: arrival.regionID)
            return decision
        }

        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.threadIdentifier = Self.threadIdentifier
        content.categoryIdentifier = Self.arrivalCategoryIdentifier

        // **How loud, and the one thing this app will not do.** A band below
        // normal arrives silently in Notification Centre rather than as a
        // banner. Nothing here is ever Time Sensitive: Apple reserves that for
        // what needs attention *now*, and using it to win attention for a
        // restaurant tip is how an app's notifications get switched off by
        // somebody who felt tricked. `NotificationInterruption` has no case
        // that would allow it — see its doc comment.
        //
        // Nil means this is a re-render of a reminder already scheduled, so
        // it keeps the ordinary treatment rather than inventing a new one.
        switch decision?.interruption ?? .active {
        case .passive:
            content.interruptionLevel = .passive
            content.sound = nil
        case .active:
            content.interruptionLevel = .active
            content.sound = .default
        }

        // What iOS uses to sort a notification summary. The same deterministic
        // score out of a hundred — see `NotificationScore.relevance`.
        if let relevance = decision?.relevance {
            content.relevanceScore = relevance
        }
        content.userInfo = [
            Self.cardIDKey: reminder.cardID.uuidString,
            Self.recommendationIDKey: snapshot.id.uuidString
        ]
        // The coloured chip on the trailing edge. Optional on purpose — see
        // `ReminderBadge`: a picture that failed to draw is not a reason to
        // withhold the sentence.
        if let badge = ReminderBadge.attachment(for: reminder.category) {
            content.attachments = [badge]
        }

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
        return decision
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
        let userInfo = response.notification.request.content.userInfo
        let recommendationID = (userInfo[Self.recommendationIDKey] as? String)
            .flatMap(UUID.init(uuidString:))

        // An action is an answer, not an opening. Somebody who taps "Not here"
        // has told us something specific and has not asked to see a card —
        // counting it as an open would inflate the one number that says
        // whether these reminders are worth anything.
        if let feedback = NotificationFeedback(rawValue: response.actionIdentifier) {
            if let recommendationID { onFeedback(recommendationID, feedback) }
            return
        }

        // The suggestion first: a tap counts even if the card it named has
        // been removed in the meantime, and that case is exactly the one
        // worth being able to count.
        if let recommendationID {
            onOpened(recommendationID)
        }

        guard let raw = userInfo[Self.cardIDKey] as? String,
              let id = UUID(uuidString: raw)
        else { return }
        cardToOpen = id
        log.notice("reminder tapped, opening a card")
    }
}
