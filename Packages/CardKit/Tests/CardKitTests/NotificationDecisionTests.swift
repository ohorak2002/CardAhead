import XCTest
@testable import CardKit

/// Whether a recommendation is worth interrupting somebody for.
///
/// Every test here states a whole situation and asks one question of it. The
/// engine reads no clock and owns no state, so "what would you have done at
/// 11pm on a Tuesday after three notifications" is a literal, not a wait.
final class NotificationDecisionTests: XCTestCase {

    // MARK: - Building a situation

    private let calendar = Calendar(identifier: .gregorian)

    private func at(_ hour: Int, _ minute: Int = 0, day: Int = 15) -> Date {
        var parts = DateComponents()
        parts.year = 2026
        parts.month = 8
        parts.day = day
        parts.hour = hour
        parts.minute = minute
        return calendar.date(from: parts) ?? Date()
    }

    /// Noon, so nothing accidentally lands in quiet hours.
    private var noon: Date { at(12) }

    private func engine(_ intensity: NotificationIntensity = .balanced) -> NotificationDecisionEngine {
        NotificationDecisionEngine(policy: NotificationPolicy(intensity: intensity))
    }

    /// Wallets are built here rather than taken from `CardCatalog`, and that
    /// is deliberate. Every number in this file is a threshold, and a test
    /// pinned to Amex Gold's real dining rate would start failing the day an
    /// issuer re-audit moved it — reporting a policy bug that is nothing of
    /// the kind. Cash back, so a rate of 4 is four cents on the dollar and the
    /// arithmetic behind each assertion can be read.
    private func wallet(_ rates: [Double], on category: SpendingCategory = .dining) -> [Card] {
        rates.enumerated().map { index, rate in
            Card(issuer: "Test", name: "Card " + String(index + 1), rules: [
                CategoryRule(category: category, rate: rate),
                CategoryRule(category: .base, rate: 1)
            ])
        }
    }

    /// Example A's wallet: 4% here, 3% here, 2% here. A real decision.
    private var contestedWallet: [Card] { wallet([4, 3, 2]) }

    /// A wallet with a real hotel bonus. The dining wallet pays its base rate
    /// at a hotel, and the ranking engine would refuse to say anything at all.
    private var hotelWallet: [Card] { wallet([5, 2], on: .hotels) }

    private func arrival(at merchant: Merchant, on date: Date) -> PendingArrival {
        PendingArrival(
            regionID: RegionPlanner.regionID(for: merchant),
            merchant: merchant,
            enteredAt: date,
            confirmAt: date
        )
    }

    /// The whole pipeline, as the app runs it: rank, write the words, then
    /// build the thing the policy judges.
    private func candidate(
        at merchant: Merchant,
        cards: [Card]? = nil,
        on date: Date? = nil,
        movement: ArrivalMovement = .unknown
    ) -> NotificationCandidate? {
        let when = date ?? noon
        let assessment = RecommendationEngine().assess(
            for: arrival(at: merchant, on: when),
            cards: cards ?? contestedWallet,
            asOf: when
        )
        return NotificationCandidate(
            merchant: merchant,
            assessment: assessment,
            movement: movement,
            asOf: when,
            calendar: calendar
        )
    }

    private var bistro: Merchant {
        Fixture.merchant("bistro", category: .dining, metersNorth: 20, name: "Corner Bistro")
    }

    private var otherBistro: Merchant {
        Fixture.merchant("other-bistro", category: .dining, metersNorth: 60, name: "Second Bistro")
    }

    private var hotel: Merchant {
        Fixture.merchant("hotel", category: .hotels, metersNorth: 40, name: "The Grand")
    }

    /// A sent notification, as the history would have stored it.
    private func sent(
        merchantID: String = "somewhere",
        category: SpendingCategory = .dining,
        identity: String = "unrelated",
        at date: Date
    ) -> NotificationRecord {
        NotificationRecord(
            date: date,
            merchantID: merchantID,
            category: category,
            identityKey: identity,
            score: 70,
            band: .normal,
            wasSent: true
        )
    }

    /// A failing assertion here is almost always a weight being wrong, so
    /// the message is the whole arithmetic rather than the total on its own.
    private func describe(_ decision: NotificationDecision) -> String {
        let lines = decision.score.components.map { "  " + $0.label + " " + String($0.points) }
        return "total " + String(decision.score.total) + "\n" + lines.joined(separator: "\n")
    }

    private func history(_ records: [NotificationRecord]) -> NotificationHistory {
        var history = NotificationHistory()
        for record in records.sorted(by: { $0.date < $1.date }) { history.record(record) }
        return history
    }

    // MARK: - The ordinary case

    /// Example A from the brief: a restaurant, a real winner, a quiet day.
    func testAGenuineChoiceWithNothingRecentGoesOut() throws {
        let candidate = try XCTUnwrap(self.candidate(at: bistro))
        let decision = engine().decide(
            candidate, history: NotificationHistory(), at: noon, calendar: calendar
        )

        XCTAssertTrue(decision.shouldNotify, describe(decision))
        XCTAssertNil(decision.suppression)
        // Lands in the "normal" band, so it arrives as a banner rather than
        // waiting silently in Notification Centre.
        XCTAssertEqual(decision.band, .normal)
        XCTAssertEqual(decision.interruption, .active)
    }

    /// The score has to be readable, or it cannot be tuned.
    func testTheScoreShowsItsWorking() throws {
        let candidate = try XCTUnwrap(self.candidate(at: bistro))
        let score = engine().score(
            candidate, history: NotificationHistory(), at: noon, calendar: calendar
        )

        XCTAssertFalse(score.components.isEmpty)
        XCTAssertEqual(
            score.components.reduce(0) { $0 + $1.points },
            score.rawTotal,
            accuracy: 0.0001
        )
        XCTAssertTrue(score.components.contains { $0.label == "Card advantage" })
        XCTAssertTrue(score.components.contains { $0.label == "Cards to choose between" })
    }

    /// Clamped, so the bands mean what they say.
    func testTheTotalNeverLeavesTheBands() {
        var score = NotificationScore()
        score.add("Enormous", 400)
        XCTAssertEqual(score.total, 100)
        XCTAssertEqual(score.band, .high)
        XCTAssertEqual(score.relevance, 1)

        var negative = NotificationScore()
        negative.add("Awful", -400)
        XCTAssertEqual(negative.total, 0)
        XCTAssertEqual(negative.band, .suppress)
    }

    // MARK: - Cooldowns

    /// Example C: back at the same restaurant half an hour later.
    func testTheSameShopIsLeftAloneAfterwards() throws {
        let candidate = try XCTUnwrap(self.candidate(at: bistro))
        let past = history([sent(merchantID: bistro.id, at: at(11, 30))])

        let decision = engine().decide(candidate, history: past, at: noon, calendar: calendar)
        XCTAssertFalse(decision.shouldNotify)
        XCTAssertEqual(decision.suppression, .merchantCooldown)
        XCTAssertNotNil(decision.nextEligible)
    }

    /// Example B: a different restaurant ten minutes later.
    func testTheSameKindOfShopIsLeftAloneForLess() throws {
        let candidate = try XCTUnwrap(self.candidate(at: otherBistro))
        let past = history([sent(merchantID: bistro.id, category: .dining, at: at(11, 50))])

        let decision = engine().decide(candidate, history: past, at: noon, calendar: calendar)
        XCTAssertFalse(decision.shouldNotify)
        XCTAssertEqual(decision.suppression, .categoryCooldown)
    }

    /// A category cooldown must not silence a different category.
    func testADifferentCategoryIsNotOnTheSameClock() throws {
        let candidate = try XCTUnwrap(self.candidate(at: hotel, cards: hotelWallet))
        let past = history([sent(merchantID: bistro.id, category: .dining, at: at(11, 50))])

        let decision = engine().decide(candidate, history: past, at: noon, calendar: calendar)
        XCTAssertTrue(decision.shouldNotify, String(describing: decision.suppression))
    }

    /// And once the clock has run out, it stops applying.
    func testACooldownExpires() throws {
        let candidate = try XCTUnwrap(self.candidate(at: bistro))
        // Balanced leaves a shop alone for 24 hours.
        let past = history([sent(merchantID: bistro.id, at: at(12, 0, day: 13))])

        let decision = engine().decide(candidate, history: past, at: noon, calendar: calendar)
        XCTAssertTrue(decision.shouldNotify, String(describing: decision.suppression))
    }

    // MARK: - Saying the same thing twice

    /// The engine runs several times per suggestion — on entry, on a wallet
    /// edit, on a location fix. Object identity cannot tell those apart.
    func testTheSameRecommendationRecalculatedIsNotANewOne() throws {
        let first = try XCTUnwrap(candidate(at: bistro, on: at(9)))
        let again = try XCTUnwrap(candidate(at: bistro, on: at(9, 30)))
        XCTAssertEqual(first.identity, again.identity)
        XCTAssertNotEqual(first.snapshot.id, again.snapshot.id, "a fresh snapshot each run")
    }

    func testADuplicateIsSuppressedWithItsOwnReason() throws {
        let candidate = try XCTUnwrap(self.candidate(at: bistro))
        let past = history([
            sent(merchantID: bistro.id, identity: candidate.identity.key, at: at(11, 55))
        ])

        let decision = engine().decide(candidate, history: past, at: noon, calendar: calendar)
        XCTAssertEqual(decision.suppression, .duplicate)
    }

    /// Change the card, and there is genuinely something new to say.
    func testADifferentCardIsADifferentRecommendation() throws {
        let gold = try XCTUnwrap(candidate(at: bistro))
        let savorOnly = try XCTUnwrap(
            candidate(at: bistro, cards: [CardCatalog.capitalOneSavor, CardCatalog.citiDoubleCash])
        )
        XCTAssertNotEqual(gold.identity, savorOnly.identity)
    }

    /// Floating-point noise must not defeat the whole mechanism.
    func testIdentityIsStableAcrossFloatingPointNoise() {
        let card = UUID()
        let clean = RecommendationIdentity(
            merchantID: "m", category: .dining, cardID: card,
            appliedRate: 4, hasActivationNudge: false
        )
        let noisy = RecommendationIdentity(
            merchantID: "m", category: .dining, cardID: card,
            appliedRate: 4 + 1e-12, hasActivationNudge: false
        )
        XCTAssertEqual(clean, noisy)
    }

    // MARK: - The day's budget

    func testTheThirdNotificationIsTheLastOrdinaryOne() throws {
        let candidate = try XCTUnwrap(self.candidate(at: bistro))
        let past = history([
            sent(merchantID: "a", category: .gas, at: at(8)),
            sent(merchantID: "b", category: .groceries, at: at(9)),
            sent(merchantID: "c", category: .entertainment, at: at(10))
        ])

        let decision = engine().decide(candidate, history: past, at: noon, calendar: calendar)
        XCTAssertFalse(decision.shouldNotify)
        XCTAssertEqual(decision.suppression, .dailyBudget)
    }

    /// Example E: three small ones, then a hotel. The hotel wins.
    func testAnExceptionallyValuableOpportunityOutranksASpentBudget() throws {
        let candidate = try XCTUnwrap(self.candidate(at: hotel, cards: hotelWallet))
        let past = history([
            sent(merchantID: "a", category: .gas, at: at(8)),
            sent(merchantID: "b", category: .groceries, at: at(9)),
            sent(merchantID: "c", category: .entertainment, at: at(10))
        ])

        let decision = engine().decide(candidate, history: past, at: noon, calendar: calendar)
        XCTAssertTrue(decision.shouldNotify, describe(decision))
        XCTAssertTrue(decision.overrodeBudget)
    }

    /// Yesterday's notifications are not today's problem.
    func testTheBudgetIsPerCalendarDay() throws {
        let candidate = try XCTUnwrap(self.candidate(at: bistro))
        let past = history([
            sent(merchantID: "a", category: .gas, at: at(8, 0, day: 14)),
            sent(merchantID: "b", category: .groceries, at: at(9, 0, day: 14)),
            sent(merchantID: "c", category: .entertainment, at: at(10, 0, day: 14))
        ])

        let decision = engine().decide(candidate, history: past, at: noon, calendar: calendar)
        XCTAssertTrue(decision.shouldNotify, String(describing: decision.suppression))
    }

    /// A suppressed candidate must not spend the budget it was suppressed by.
    func testASuppressedCandidateDoesNotCountAgainstTheBudget() {
        var past = NotificationHistory()
        for hour in 8...11 {
            past.record(NotificationRecord(
                date: at(hour), merchantID: "m\(hour)", category: .dining,
                identityKey: "k\(hour)", score: 10, band: .suppress, wasSent: false,
                suppression: .belowThreshold
            ))
        }
        XCTAssertEqual(past.sentCount(on: noon, calendar: calendar), 0)
    }

    // MARK: - Is this even a choice

    /// The same 4% card, alone and in company. Alone scores lower, because
    /// there is no decision being helped with.
    func testASingleCardWalletIsAWeakerCase() throws {
        let one = try XCTUnwrap(candidate(at: bistro, cards: wallet([4])))
        let three = try XCTUnwrap(candidate(at: bistro))

        let solo = engine().score(one, history: NotificationHistory(), at: noon, calendar: calendar)
        let contested = engine().score(three, history: NotificationHistory(), at: noon, calendar: calendar)
        XCTAssertLessThan(solo.total, contested.total)
        XCTAssertEqual(one.competingCardCount, 1)
    }

    /// Example D: one card, a small win. Not worth a word.
    func testASingleCardWithASmallWinStaysQuiet() throws {
        let one = try XCTUnwrap(candidate(at: bistro, cards: wallet([2])))
        let decision = engine().decide(
            one, history: NotificationHistory(), at: noon, calendar: calendar
        )
        XCTAssertFalse(decision.shouldNotify)
        XCTAssertEqual(decision.suppression, .belowThreshold)
    }

    /// But a single card is not banned outright. The brief asks for lower
    /// priority, not silence, and a large enough win still says something.
    func testASingleCardWalletIsNotSilencedOutright() throws {
        let one = try XCTUnwrap(candidate(at: hotel, cards: wallet([5], on: .hotels)))
        let decision = engine().decide(
            one, history: NotificationHistory(), at: noon, calendar: calendar
        )
        XCTAssertEqual(one.competingCardCount, 1)
        XCTAssertTrue(decision.shouldNotify, describe(decision))
    }

    /// Eight cards that all pay the same is one answer, not eight.
    func testIdenticalCardsAreNotAChoice() {
        let flat = wallet([1, 1, 1, 1, 1, 1, 1, 1])
        let ranked = RecommendationEngine().rank(flat, in: PurchaseContext(category: .dining, date: noon))
        XCTAssertEqual(NotificationCandidate.distinctRateCount(in: ranked), 1)
    }

    // MARK: - Quiet hours

    /// Example G: a restaurant at 11:30pm.
    func testNothingGoesOutAtHalfPastEleven() throws {
        let candidate = try XCTUnwrap(self.candidate(at: bistro, on: at(23, 30)))
        let decision = engine().decide(
            candidate, history: NotificationHistory(), at: at(23, 30), calendar: calendar
        )
        XCTAssertFalse(decision.shouldNotify)
        XCTAssertEqual(decision.suppression, .quietHours)
        XCTAssertNotNil(decision.nextEligible)
    }

    /// The window crosses midnight, which is the whole difficulty.
    func testQuietHoursWrapAroundMidnight() {
        let quiet = QuietHours.standard
        XCTAssertTrue(quiet.contains(at(22, 0), calendar: calendar))
        XCTAssertTrue(quiet.contains(at(23, 59), calendar: calendar))
        XCTAssertTrue(quiet.contains(at(0, 1), calendar: calendar))
        XCTAssertTrue(quiet.contains(at(7, 59), calendar: calendar))
        XCTAssertFalse(quiet.contains(at(8, 0), calendar: calendar))
        XCTAssertFalse(quiet.contains(at(21, 59), calendar: calendar))
        XCTAssertFalse(quiet.contains(at(12, 0), calendar: calendar))
    }

    func testQuietHoursSwitchedOffAreNotQuiet() {
        var quiet = QuietHours.standard
        quiet.isEnabled = false
        XCTAssertFalse(quiet.contains(at(23, 30), calendar: calendar))
    }

    /// Both ends dragged to the same place means "off", not "always".
    func testAnEmptyQuietWindowIsNotTwentyFourHours() {
        let quiet = QuietHours(startMinutes: 8 * 60, endMinutes: 8 * 60)
        XCTAssertFalse(quiet.contains(at(8, 0), calendar: calendar))
        XCTAssertFalse(quiet.contains(at(3, 0), calendar: calendar))
    }

    /// A suppression that time will fix says when.
    func testQuietHoursSayWhenTheyEnd() throws {
        let end = try XCTUnwrap(QuietHours.standard.end(after: at(23, 30), calendar: calendar))
        XCTAssertEqual(calendar.component(.hour, from: end), 8)
        XCTAssertNil(QuietHours.standard.end(after: noon, calendar: calendar))
    }

    // MARK: - The user's own instructions

    func testASwitchedOffCategorySaysNothing() throws {
        var policy = NotificationPolicy()
        policy.setCategory(.dining, enabled: false)
        let candidate = try XCTUnwrap(self.candidate(at: bistro))

        let decision = NotificationDecisionEngine(policy: policy).decide(
            candidate, history: NotificationHistory(), at: noon, calendar: calendar
        )
        XCTAssertEqual(decision.suppression, .categoryDisabled)
    }

    func testAMutedShopSaysNothing() throws {
        var policy = NotificationPolicy()
        policy.mute(merchantID: bistro.id, for: .week, from: noon, calendar: calendar)
        let candidate = try XCTUnwrap(self.candidate(at: bistro))

        let decision = NotificationDecisionEngine(policy: policy).decide(
            candidate, history: NotificationHistory(), at: noon, calendar: calendar
        )
        XCTAssertEqual(decision.suppression, .merchantMuted)
    }

    func testAMuteForTodayExpiresTomorrow() {
        var policy = NotificationPolicy()
        policy.mute(merchantID: "m", for: .today, from: at(14), calendar: calendar)
        XCTAssertTrue(policy.isMuted(merchantID: "m", at: at(23, 59)))
        XCTAssertFalse(policy.isMuted(merchantID: "m", at: at(9, 0, day: 16)))
    }

    func testAlwaysMutedStaysMuted() {
        var policy = NotificationPolicy()
        policy.mute(merchantID: "m", for: .always, from: noon, calendar: calendar)
        XCTAssertTrue(policy.isMuted(merchantID: "m", at: at(12, 0, day: 15).addingTimeInterval(86_400 * 900)))
        policy.pruneExpiredMutes(asOf: at(12, 0, day: 15).addingTimeInterval(86_400 * 900))
        XCTAssertTrue(policy.isMuted(merchantID: "m", at: noon))
    }

    func testExpiredMutesArePrunedAway() {
        var policy = NotificationPolicy()
        policy.mute(merchantID: "m", for: .today, from: noon, calendar: calendar)
        policy.pruneExpiredMutes(asOf: at(9, 0, day: 17))
        XCTAssertTrue(policy.mutedMerchants.isEmpty)
    }

    /// A suppression somebody asked for is not a tuning problem, and the
    /// debug screen needs to be able to tell.
    func testTheUsersOwnChoicesAreMarkedAsSuch() {
        XCTAssertTrue(SuppressionReason.quietHours.isUserChoice)
        XCTAssertTrue(SuppressionReason.merchantMuted.isUserChoice)
        XCTAssertTrue(SuppressionReason.categoryDisabled.isUserChoice)
        XCTAssertFalse(SuppressionReason.belowThreshold.isUserChoice)
        XCTAssertFalse(SuppressionReason.dailyBudget.isUserChoice)
    }

    // MARK: - Confidence

    /// Example H: a vague place and a marginal suggestion.
    func testAVaguePlaceWithAMarginalWinStaysQuiet() throws {
        var mall = Fixture.merchant("mall", category: .dining, metersNorth: 20, name: "Food Court")
        mall.confidence = .categoryOnly
        mall.placeTypes = ["food"]

        // Two cards a hair apart: a real edge, and a small one.
        let candidate = try XCTUnwrap(self.candidate(at: mall, cards: wallet([2, 1])))
        XCTAssertTrue(candidate.isWeaklyTyped)

        let decision = engine().decide(
            candidate, history: NotificationHistory(), at: noon, calendar: calendar
        )
        XCTAssertFalse(decision.shouldNotify)
        XCTAssertEqual(decision.suppression, .lowConfidence)
    }

    /// Knowing the exact business is worth more than knowing the kind.
    func testBeingSureScoresHigherThanGuessing() throws {
        var vague = bistro
        vague.confidence = .categoryOnly

        let sure = try XCTUnwrap(candidate(at: bistro))
        let unsure = try XCTUnwrap(candidate(at: vague))

        let sureScore = engine().score(sure, history: NotificationHistory(), at: noon, calendar: calendar)
        let unsureScore = engine().score(unsure, history: NotificationHistory(), at: noon, calendar: calendar)
        XCTAssertGreaterThan(sureScore.total, unsureScore.total)
    }

    /// A catch-all type is a weaker claim than a specific one, and a name the
    /// map overrides is not a guess at all.
    func testWeakTypingIsRecognised() {
        XCTAssertTrue(MerchantCategoryMap.isWeaklyTyped(placeTypes: ["food"]))
        XCTAssertTrue(MerchantCategoryMap.isWeaklyTyped(placeTypes: ["shopping_mall"]))
        XCTAssertFalse(MerchantCategoryMap.isWeaklyTyped(placeTypes: ["pizza_restaurant", "food"]))
        XCTAssertFalse(MerchantCategoryMap.isWeaklyTyped(placeTypes: ["gas_station"]))
        XCTAssertFalse(
            MerchantCategoryMap.isWeaklyTyped(placeTypes: ["food"], merchantName: "Costco Wholesale")
        )
    }

    // MARK: - Movement

    /// Example F: driving past at speed.
    func testDrivingPastIsNotArriving() throws {
        let candidate = try XCTUnwrap(self.candidate(at: bistro, movement: .passingThrough))
        let decision = engine().decide(
            candidate, history: NotificationHistory(), at: noon, calendar: calendar
        )
        XCTAssertFalse(decision.shouldNotify)
        XCTAssertEqual(decision.suppression, .movingTooFast)
    }

    func testNoFixMeansNoOpinion() {
        XCTAssertEqual(ArrivalMovement.from(speedMetersPerSecond: nil), .unknown)
        XCTAssertEqual(ArrivalMovement.from(speedMetersPerSecond: -1), .unknown)
        XCTAssertEqual(ArrivalMovement.from(speedMetersPerSecond: 0), .arrived)
        XCTAssertEqual(ArrivalMovement.from(speedMetersPerSecond: 1.4), .arrived)
        XCTAssertEqual(ArrivalMovement.from(speedMetersPerSecond: 25), .passingThrough)
    }

    // MARK: - Running out

    /// Urgency and relevance together, never urgency alone: the credit is
    /// about to expire *and* this is the shop it applies to.
    func testSomethingRunningOutScoresHigher() throws {
        let plain = wallet([4, 3])
        var closing = plain
        // A tiny bonus, so it cannot win the ranking on its own and change
        // which card this test is about. What it carries is a deadline.
        closing[0] = Fixture.withWelcomeBonus(
            closing[0], rewardUnits: 100, required: 4_000, spent: 3_000,
            deadline: at(12, 0, day: 17)
        )

        let ordinary = try XCTUnwrap(candidate(at: bistro, cards: plain))
        let urgent = try XCTUnwrap(candidate(at: bistro, cards: closing))

        XCTAssertNil(ordinary.expiringInDays)
        XCTAssertEqual(urgent.expiringInDays, 2)

        let calm = engine().score(ordinary, history: NotificationHistory(), at: noon, calendar: calendar)
        let pressing = engine().score(urgent, history: NotificationHistory(), at: noon, calendar: calendar)
        XCTAssertGreaterThan(pressing.total, calm.total)
    }

    /// A permanent rate has no clock, and must not be given one.
    func testAPermanentRateIsNeverUrgent() throws {
        let candidate = try XCTUnwrap(self.candidate(at: bistro))
        XCTAssertNil(candidate.expiringInDays)
        let score = engine().score(candidate, history: NotificationHistory(), at: noon, calendar: calendar)
        XCTAssertFalse(score.components.contains { $0.label == "Running out" })
    }

    // MARK: - Intensity

    /// The four settings are four sets of numbers over one engine, so the
    /// same situation must move monotonically across them.
    func testIntensityOnlyMovesTheNumbers() throws {
        let candidate = try XCTUnwrap(self.candidate(at: bistro))
        let budgets = NotificationIntensity.allCases.map { $0.thresholds.dailyBudget }
        XCTAssertEqual(budgets, budgets.sorted(), "more intensity, never fewer")

        let bars = NotificationIntensity.allCases.map { $0.thresholds.minimumScore }
        XCTAssertEqual(bars, bars.sorted().reversed(), "more intensity, never a higher bar")

        // And the same candidate is scored identically whatever the setting —
        // intensity changes the bar, never the arithmetic.
        let scores = NotificationIntensity.allCases.map {
            engine($0).score(candidate, history: NotificationHistory(), at: noon, calendar: calendar).total
        }
        XCTAssertEqual(Set(scores).count, 1)
    }

    /// One modest win, judged by all four settings. The situation never
    /// changes; only the bar does.
    func testOneModestWinIsJudgedDifferentlyByEachSetting() throws {
        // 2% against 1% — a real edge, and a small one.
        let candidate = try XCTUnwrap(self.candidate(at: bistro, cards: wallet([2, 1])))

        let answers = NotificationIntensity.allCases.map { intensity in
            engine(intensity).decide(
                candidate, history: NotificationHistory(), at: noon, calendar: calendar
            ).shouldNotify
        }
        XCTAssertEqual(
            answers,
            [false, false, true, true],
            "minimal, balanced, helpful, frequent"
        )
    }

    func testBalancedIsTheDefault() {
        XCTAssertEqual(NotificationPolicy().intensity, .balanced)
        XCTAssertEqual(NotificationPolicy().thresholds.dailyBudget, 3)
        XCTAssertTrue(NotificationPolicy().quietHours.isEnabled)
        XCTAssertTrue(NotificationPolicy().disabledCategories.isEmpty)
    }

    // MARK: - Relevance and loudness

    func testRelevanceIsTheScoreOutOfAHundred() throws {
        let candidate = try XCTUnwrap(self.candidate(at: bistro))
        let decision = engine().decide(
            candidate, history: NotificationHistory(), at: noon, calendar: calendar
        )
        XCTAssertEqual(decision.relevance, decision.score.total / 100, accuracy: 0.0001)
        XCTAssertGreaterThanOrEqual(decision.relevance, 0)
        XCTAssertLessThanOrEqual(decision.relevance, 1)
    }

    /// Nothing this app sends is urgent. There is deliberately no case to
    /// choose that would make it so.
    func testNothingIsEverLouderThanActive() {
        XCTAssertEqual(NotificationInterruption.allCases.count, 2)
        XCTAssertFalse(NotificationInterruption.allCases.contains { $0.rawValue.contains("time") })
        XCTAssertFalse(NotificationInterruption.allCases.contains { $0.rawValue.contains("critical") })
    }

    // MARK: - History

    func testHistoryCountsOnlyWhatWasSent() {
        var past = NotificationHistory()
        past.record(sent(at: at(9)))
        past.record(NotificationRecord(
            date: at(10), merchantID: "b", category: .gas, identityKey: "x",
            score: 12, band: .suppress, wasSent: false, suppression: .belowThreshold
        ))
        XCTAssertEqual(past.records.count, 2)
        XCTAssertEqual(past.sentCount(on: noon, calendar: calendar), 1)
    }

    func testHistoryForgetsOldRows() {
        var past = NotificationHistory()
        past.record(sent(at: at(12, 0, day: 1)))
        past.record(sent(at: at(12, 0, day: 15)))
        XCTAssertEqual(past.records.count, 1)
    }

    func testHistorySurvivesBeingWrittenAndReadBack() throws {
        var past = NotificationHistory()
        past.record(sent(merchantID: "bistro", identity: "k", at: at(11)))

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(
            NotificationHistory.self, from: try encoder.encode(past)
        )

        XCTAssertEqual(restored.sentCount(on: noon, calendar: calendar), 1)
        XCTAssertEqual(restored.lastSent(merchantID: "bistro")?.identityKey, "k")
    }

    func testFeedbackLandsOnTheRowItAnswers() {
        var past = NotificationHistory()
        let record = sent(at: at(11))
        past.record(record)
        past.note(.usedIt, forRecordID: record.id)
        XCTAssertEqual(past.records.first?.feedback, .usedIt)
    }

    /// A tap on something already forgotten changes nothing and crashes
    /// nothing.
    func testFeedbackForAForgottenRowIsHarmless() {
        var past = NotificationHistory()
        past.note(.notUseful, forRecordID: UUID())
        XCTAssertTrue(past.records.isEmpty)
    }

    // MARK: - What a suggestion is probably worth

    /// The ordering is the whole claim. The magnitudes are estimates and the
    /// doc comment says so; what must be true is that a hotel outranks a
    /// coffee.
    func testValueOrdersTheObviousCasesCorrectly() {
        let coffee = OpportunityValue.estimatedCents(edgeCentsPerDollar: 1, category: .dining)
        let shop = OpportunityValue.estimatedCents(edgeCentsPerDollar: 1, category: .groceries)
        let stay = OpportunityValue.estimatedCents(edgeCentsPerDollar: 1, category: .hotels)
        XCTAssertLessThan(coffee, shop)
        XCTAssertLessThan(shop, stay)
    }

    func testANegativeEdgeIsWorthNothingRatherThanSomething() {
        XCTAssertEqual(
            OpportunityValue.estimatedCents(edgeCentsPerDollar: -3, category: .hotels), 0
        )
    }

    // MARK: - The policy never revives what the engine refused

    func testAnEngineSilenceNeverBecomesACandidate() {
        let flat = [CardCatalog.citiDoubleCash, CardCatalog.wellsFargoActiveCash]
        XCTAssertNil(candidate(at: bistro, cards: flat))
        XCTAssertNil(candidate(at: bistro, cards: []))
    }
}
