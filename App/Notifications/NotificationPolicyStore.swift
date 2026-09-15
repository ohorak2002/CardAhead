import Foundation
import Observation
import os
import CardKit

/// The notification policy and the record of what it has decided, kept on
/// disk.
///
/// **Why this is its own store rather than a field on `RegionMonitor`.** The
/// two things in here are read and written by three different parts of the
/// app at three different moments: the region monitor consults them when a
/// geofence fires (often with the app suspended and seconds to act), the
/// settings screen writes the policy, and the notification centre writes
/// somebody's answer back into the history when they tap an action — which
/// can happen while the app is being *launched* by that tap. A field on the
/// monitor would have made the monitor a dependency of the settings screen,
/// which is a large object to drag into a form.
///
/// **Nothing here reads the clock.** Every method takes a date, because every
/// question it answers is one a test has to be able to ask about a Tuesday
/// three weeks ago.
@Observable
final class NotificationPolicyStore {

    private(set) var policy: NotificationPolicy
    private(set) var history: NotificationHistory

    private let fileURL: URL
    private let log = Logger(subsystem: AppLog.subsystem, category: "notification-policy")

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultURL()
        let restored = Self.load(from: self.fileURL)
        policy = restored?.policy ?? NotificationPolicy()
        history = restored?.history ?? NotificationHistory()
    }

    var engine: NotificationDecisionEngine { NotificationDecisionEngine(policy: policy) }

    // MARK: - Deciding

    /// The one place a decision is made, so nothing else in the app has to
    /// know the order the gates run in.
    func decide(
        _ candidate: NotificationCandidate,
        at date: Date = Date(),
        calendar: Calendar = .current
    ) -> NotificationDecision {
        engine.decide(candidate, history: history, at: date, calendar: calendar)
    }

    /// Writes down what was decided — sent or not.
    ///
    /// **Called for a suppression as well as for a send, and that is the
    /// point.** A history that only holds what went out can enforce a budget
    /// and nothing else; it cannot answer "why have I heard nothing all
    /// afternoon", which is the one question somebody asks when this feature
    /// looks broken.
    @discardableResult
    func record(
        _ decision: NotificationDecision,
        for candidate: NotificationCandidate,
        at date: Date = Date()
    ) -> NotificationRecord {
        let record = NotificationRecord(
            date: date,
            merchantID: candidate.merchantID,
            merchantName: candidate.merchantName,
            category: candidate.category,
            cardID: candidate.reminder.cardID,
            cardName: candidate.reminder.cardName,
            identityKey: candidate.identity.key,
            score: decision.score.total,
            band: decision.band,
            wasSent: decision.shouldNotify,
            suppression: decision.suppression,
            recommendationID: candidate.snapshot.id
        )
        history.record(record)
        save()
        return record
    }

    /// Corrects a row that said "sent" when nothing was.
    ///
    /// The narrow case it exists for: the wallet is edited in the
    /// milliseconds between the ranking engine deciding there is something to
    /// say and the notification centre being handed it. The row is already
    /// written, and leaving it would charge the day's budget for a reminder
    /// nobody will ever see.
    func markNotSent(recommendationID: UUID) {
        guard let record = history.record(forRecommendationID: recommendationID) else { return }
        history.markNotSent(recordID: record.id, reason: .noMeaningfulEdge)
        save()
    }

    /// Somebody tapped an action on the notification itself.
    func note(_ feedback: NotificationFeedback, forRecommendationID id: UUID) {
        guard let record = history.record(forRecommendationID: id) else { return }
        history.note(feedback, forRecordID: record.id)
        save()
    }

    func record(forRecommendationID id: UUID) -> NotificationRecord? {
        history.record(forRecommendationID: id)
    }

    // MARK: - Changing the policy

    func setIntensity(_ intensity: NotificationIntensity) {
        policy.intensity = intensity
        save()
    }

    func setCategory(_ category: SpendingCategory, enabled: Bool) {
        policy.setCategory(category, enabled: enabled)
        save()
    }

    func setQuietHours(_ quietHours: QuietHours) {
        policy.quietHours = quietHours
        save()
    }

    func mute(
        merchantID: String,
        for duration: NotificationPolicy.MuteDuration,
        from date: Date = Date(),
        calendar: Calendar = .current
    ) {
        policy.mute(merchantID: merchantID, for: duration, from: date, calendar: calendar)
        save()
    }

    func unmute(merchantID: String) {
        policy.unmute(merchantID: merchantID)
        save()
    }

    /// For the "forget everything" path in Settings. The policy itself is a
    /// preference and survives; what somebody is erasing is the record.
    func clearHistory() {
        history.removeAll()
        save()
    }

    // MARK: - Persistence

    private struct Stored: Codable {
        var policy: NotificationPolicy
        var history: NotificationHistory
    }

    private static func defaultURL() -> URL {
        let directory = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL.temporaryDirectory
        return directory.appendingPathComponent("notifications.json")
    }

    private static func load(from url: URL) -> Stored? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Stored.self, from: data)
    }

    private func save() {
        // Both pruners run here rather than on a timer: this is the only
        // moment either collection is known to have changed, and a timer that
        // fires while the app is dead is not a thing.
        policy.pruneExpiredMutes()
        history.prune(asOf: Date())

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(Stored(policy: policy, history: history)) else {
            log.error("could not write the notification policy")
            return
        }
        try? data.write(to: fileURL, options: [.atomic])
    }
}
