import Foundation
import CardKit

/// Fills a wallet with catalog cards so CI's simulator can photograph screens
/// that have something on them.
///
/// **Debug builds only, and only when explicitly asked for.** `isActive`
/// compiles to a constant `false` outside `#if DEBUG`, so a release build can
/// never seed anything whatever it is launched with; and a debug build still
/// does nothing without `-CardWiseDemoSeed` on the command line, which is not
/// an argument anybody types by accident.
///
/// This exists because of the one fact that shapes this repo: development
/// happens on Windows, there is no Xcode, and until now nobody could see a
/// single screen of this app. A macOS CI runner *has* simulators, so it can
/// boot one, install the app, and take pictures — but the app opens on an
/// empty wallet, and a photograph of an empty wallet says nothing about how
/// the wallet looks. See `.github/workflows/ci.yml`.
///
/// It writes to files the launch argument names, never to the real ones, so a
/// seeded run cannot overwrite anybody's actual wallet.
enum DemoSeed {

    static let launchArgument = "-CardWiseDemoSeed"
    /// Which tab to open on. CI photographs one screen per launch rather than
    /// tapping through, because `simctl` cannot tap and a scripted tap against
    /// a UI that is being redesigned is the least reliable part of any
    /// screenshot pipeline.
    static let tabArgument = "-CardWiseDemoTab"

    /// The tab name CI asked for, when it asked for one.
    static var requestedTab: String? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: tabArgument),
              arguments.indices.contains(index + 1)
        else { return nil }
        return arguments[index + 1]
        #else
        return nil
        #endif
    }

    /// True when this process was started to be photographed.
    static var isActive: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains(launchArgument)
        #else
        return false
        #endif
    }

    /// A directory of its own, so nothing here can touch `wallet.json` or
    /// `impact.json`.
    static func directory() -> URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL.temporaryDirectory
        let directory = base.appendingPathComponent("DemoSeed", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func walletURL() -> URL { directory().appendingPathComponent("wallet.json") }
    static func impactURL() -> URL { directory().appendingPathComponent("impact.json") }
    static func regionsURL() -> URL { directory().appendingPathComponent("regions.json") }

    /// Three cards that between them show every shape the UI has to handle: a
    /// points card with a cap, a rotating-quarter card with the bonus not
    /// switched on, and a flat cash back card.
    static var cards: [Card] {
        [CardCatalog.amexGold, CardCatalog.chaseFreedomFlex, CardCatalog.citiDoubleCash]
    }

    /// A ledger with enough in it that the impact screen has bars to draw.
    /// Fabricated, and only ever inside a seeded debug run — nothing here can
    /// reach a real ledger, which is why the seed writes to its own file.
    static func ledger(for wallet: [Card], asOf date: Date = Date()) -> ImpactLedger {
        var ledger = ImpactLedger()
        let engine = RecommendationEngine()

        let script: [(SpendingCategory, Money, Int)] = [
            (.dining, 85, 2),
            (.groceries, 140, 5),
            (.travel, 420, 9),
            (.dining, 62, 12)
        ]

        for (category, spend, daysAgo) in script {
            let when = date.addingTimeInterval(-Double(daysAgo) * 24 * 60 * 60)
            let context = PurchaseContext(category: category, confidence: .exact, date: when)
            guard let recommendation = engine.recommend(from: wallet, in: context) else { continue }
            let snapshot = RecommendationSnapshot(recommendation, context: context)

            ledger.recordGenerated(snapshot)
            ledger.recordShown(snapshot, at: when)
            ledger.recordAnswer(.recommendationAccepted, for: snapshot.id, at: when)
            ledger.recordPurchase(spend, for: snapshot.id, at: when)
        }

        // Restraint is half the story the impact screen tells.
        ledger.recordSuppressed(.throttled, category: .dining, at: date.addingTimeInterval(-3600))
        ledger.recordSuppressed(.noMeaningfulEdge, category: .gas, at: date.addingTimeInterval(-7200))
        return ledger
    }

    /// Writes the seed files. Called once, before any store reads them.
    static func install() {
        guard isActive else { return }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let wallet = cards
        if let data = try? encoder.encode(wallet) {
            try? data.write(to: walletURL(), options: [.atomic])
        }

        struct SeededImpact: Codable {
            var ledger: ImpactLedger
            var openByRegion: [String: RecommendationSnapshot]
            var isRecording: Bool?
        }
        let impact = SeededImpact(
            ledger: ledger(for: wallet),
            openByRegion: [:],
            isRecording: true
        )
        if let data = try? encoder.encode(impact) {
            try? data.write(to: impactURL(), options: [.atomic])
        }
    }
}
