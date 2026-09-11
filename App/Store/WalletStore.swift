import Foundation
import Observation
import SwiftUI
import UIKit
import CardKit

/// A card `WalletStore.remove(_:)` just took out, and the index it came from
/// — enough to put it back exactly where it was rather than at the end of the
/// stack. `Equatable` so `undoRemove`'s deferred `clearLastRemoved()` can tell
/// whether it is still looking at the removal it was scheduled for, or a
/// later one has already superseded it.
struct RemovedCard: Equatable {
    var card: Card
    var index: Int
}

/// The user's wallet: which cards they hold, in the order they keep them.
///
/// Everything here stays on the device. There is no account, no sync, and no
/// transaction feed in v1 — every card is one the user added by hand.
///
/// A fresh install starts empty, and that is deliberate: nothing is seeded and
/// nothing is imported. `CardCatalog` is only a typing shortcut inside the add
/// flow, never a starter wallet. Do not "helpfully" preload cards here — a card
/// the user did not add is a card whose rates they never checked.
@Observable
final class WalletStore {

    /// Empty until the user adds something. `load()` leaves this alone when
    /// there is no saved file, which is the first-launch case.
    private(set) var cards: [Card] = []

    /// The card `remove(_:)` most recently took out, and where it was sitting,
    /// so a tap on "Undo" can put it back exactly where it was rather than at
    /// the end of the stack. `WalletStackView` shows this as a banner and
    /// clears it once the window on the banner passes — see `remove(_:)`.
    private(set) var lastRemoved: RemovedCard?

    private let fileURL: URL
    private let engine = RecommendationEngine()

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        load()
        // Anything left over from a session that ended before its undo window
        // closed — the app was killed, not just backgrounded — is genuinely
        // orphaned now. See `remove(_:)` for why the file survives that long.
        sweepOrphanedPhotos()
    }

    // MARK: - Reading

    func recommendation(for context: PurchaseContext) -> Recommendation? {
        engine.recommend(from: cards, in: context)
    }

    func ranking(for context: PurchaseContext) -> [CardScore] {
        engine.rank(cards, in: context)
    }

    func card(withID id: UUID) -> Card? {
        cards.first { $0.id == id }
    }

    /// Cards with a rotating bonus that still needs a click this quarter or next.
    func cardsNeedingActivation(asOf date: Date = Date()) -> [Card] {
        cards.filter { card in
            guard let program = card.rotatingProgram else { return false }
            return !program.unactivatedQuarters(asOf: date).isEmpty
        }
    }

    // MARK: - Writing

    func add(_ card: Card) {
        var copy = card
        copy.id = UUID() // a catalog template can be added more than once
        cards.append(copy)
        save()
    }

    /// Takes a card out, but leaves it undoable for a few seconds rather than
    /// asking "are you sure?" first.
    ///
    /// Its photo file is deliberately *not* deleted here — only `remove(_:)`
    /// used to, and undo would have put the card back with no picture of
    /// itself. The file now outlives the card until `sweepOrphanedPhotos()`
    /// runs, which is once the undo window has genuinely closed: on the next
    /// removal, or the next launch if the app is killed before then.
    func remove(_ card: Card) {
        guard let index = cards.firstIndex(where: { $0.id == card.id }) else { return }
        // A second removal while the first is still undoable simply replaces
        // it — only the most recent is ever undoable, matching a single
        // "Undo" toast. The first card's photo is not leaked: neither card is
        // in `cards` any more, so whichever removal's timer fires last sweeps
        // both.
        let removed = RemovedCard(card: card, index: index)
        lastRemoved = removed
        cards.remove(at: index)
        save()

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard let self, self.lastRemoved == removed else { return }
            self.clearLastRemoved()
        }
    }

    /// Puts the most recently removed card back exactly where it was.
    func undoRemove() {
        guard let removed = lastRemoved else { return }
        let index = min(max(removed.index, 0), cards.count)
        cards.insert(removed.card, at: index)
        lastRemoved = nil
        save()
    }

    /// Called once the six-second window on `remove(_:)`'s own timer runs
    /// out. Past this point the removed card's photo is swept, so it must
    /// never run while the card could still come back — which is exactly why
    /// the timer checks `lastRemoved == removed` before calling this: a
    /// removal superseded by a newer one already failed that check, and its
    /// timer becomes a no-op. The newer removal's own timer sweeps for both.
    func clearLastRemoved() {
        guard lastRemoved != nil else { return }
        lastRemoved = nil
        sweepOrphanedPhotos()
    }

    func remove(atOffsets offsets: IndexSet) {
        cards.remove(atOffsets: offsets)
        save()
    }

    func move(from source: IndexSet, to destination: Int) {
        cards.move(fromOffsets: source, toOffset: destination)
        save()
    }

    /// Used by the drag-to-reorder gesture in the stack.
    func move(id: UUID, to newIndex: Int) {
        guard let currentIndex = cards.firstIndex(where: { $0.id == id }) else { return }
        let clamped = min(max(newIndex, 0), cards.count - 1)
        guard clamped != currentIndex else { return }
        let card = cards.remove(at: currentIndex)
        cards.insert(card, at: clamped)
        save()
    }

    func togglePin(_ card: Card) {
        update(card.id) { $0.isPinned.toggle() }
    }

    func setActivated(_ activated: Bool, cardID: UUID, quarter: Quarter) {
        update(cardID) { card in
            guard var program = card.rotatingProgram,
                  let index = program.quarters.firstIndex(where: { $0.quarter == quarter })
            else { return }
            program.quarters[index].isActivated = activated
            card.rotatingProgram = program
        }
    }

    func setCapSpend(_ amount: Money, cardID: UUID, category: SpendingCategory) {
        update(cardID) { card in
            guard let index = card.rules.firstIndex(where: { $0.category == category }) else { return }
            card.rules[index].cap?.spentDollars = amount
        }
    }

    /// What the user read in their issuer's email, for a quarter nothing
    /// shipped with the app could have known. Marked as theirs, so the UI can
    /// say where it came from and a later build does not silently overwrite a
    /// number they checked themselves.
    func setRotatingCategories(
        _ categories: [SpendingCategory],
        activated: Bool,
        cardID: UUID,
        quarter: Quarter
    ) {
        update(cardID) { card in
            guard var program = card.rotatingProgram else { return }
            program.setQuarter(RotatingQuarter(
                quarter: quarter,
                categories: categories,
                isActivated: activated,
                enteredByUser: true
            ))
            card.rotatingProgram = program
        }
    }

    func setRotatingCapSpend(_ amount: Money, cardID: UUID) {
        update(cardID) { card in
            card.rotatingProgram?.cap?.spentDollars = amount
        }
    }

    func setPointValuation(_ centsPerUnit: Double, cardID: UUID) {
        update(cardID) { $0.currency.centsPerUnit = centsPerUnit }
    }

    /// The point currencies actually present in the wallet, one entry each.
    ///
    /// Cash back is excluded on purpose: a cent is worth a cent, and offering
    /// to revalue it would only invite someone to break their own ranking.
    var valuablePointCurrencies: [RewardCurrency] {
        var seen: Set<String> = []
        return cards
            .map(\.currency)
            .filter { $0.style == .multiplier }
            .filter { seen.insert($0.name).inserted }
            .sorted { $0.name < $1.name }
    }

    /// Valuation belongs to the currency, not the card. Someone holding two
    /// Chase cards should not have to state what a Chase point is worth twice.
    func setValuation(_ centsPerUnit: Double, forCurrencyNamed name: String) {
        for index in cards.indices where cards[index].currency.name == name {
            cards[index].currency.centsPerUnit = centsPerUnit
        }
        save()
    }

    func valuation(forCurrencyNamed name: String) -> Double {
        cards.first { $0.currency.name == name }?.currency.centsPerUnit ?? 1.0
    }

    /// Everything, including the photos. There is no account and no backup, so
    /// this is genuinely irreversible — the caller must confirm first.
    func eraseEverything() {
        for card in cards {
            if let name = card.photoFilename { deletePhoto(named: name) }
        }
        cards = []
        save()
    }

    func replace(_ card: Card) {
        guard let index = cards.firstIndex(where: { $0.id == card.id }) else { return }
        cards[index] = card
        save()
    }

    private func update(_ id: UUID, _ change: (inout Card) -> Void) {
        guard let index = cards.firstIndex(where: { $0.id == id }) else { return }
        change(&cards[index])
        save()
    }

    // MARK: - Card photos

    /// Photos live next to the wallet file rather than inside it: a base64
    /// image in the JSON would bloat every read of the card list.
    @ObservationIgnored private var photoCache: [String: Image] = [:]

    func photo(for card: Card) -> Image? {
        guard let name = card.photoFilename else { return nil }
        if let cached = photoCache[name] { return cached }
        let url = Self.photosDirectory().appendingPathComponent(name)
        guard let data = try? Data(contentsOf: url),
              let image = UIImage(data: data)
        else { return nil }
        let rendered = Image(uiImage: image)
        photoCache[name] = rendered
        return rendered
    }

    /// Writes a photo and hands back the filename to store on the card.
    /// Downscaled to card size first — a full camera frame is megabytes, and
    /// nothing above card resolution is ever drawn.
    func storePhoto(_ image: UIImage) -> String? {
        let width: CGFloat = 640
        let size = CGSize(width: width, height: (width / 1.586).rounded())
        let renderer = UIGraphicsImageRenderer(size: size)
        let scaled = renderer.image { _ in
            // cover, never letterbox
            let factor = max(size.width / image.size.width, size.height / image.size.height)
            let drawn = CGSize(width: image.size.width * factor, height: image.size.height * factor)
            image.draw(in: CGRect(
                x: (size.width - drawn.width) / 2,
                y: (size.height - drawn.height) / 2,
                width: drawn.width, height: drawn.height
            ))
        }
        guard let data = scaled.jpegData(compressionQuality: 0.82) else { return nil }

        let directory = Self.photosDirectory()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = UUID().uuidString + ".jpg"
        do {
            try data.write(to: directory.appendingPathComponent(name), options: [.atomic])
            return name
        } catch {
            return nil
        }
    }

    /// Swaps a card's photo and cleans up the file it replaces, so editing a
    /// card repeatedly does not leave a pile of orphaned images behind.
    func setPhoto(_ image: UIImage?, on card: inout Card) {
        if let existing = card.photoFilename { deletePhoto(named: existing) }
        card.photoFilename = image.flatMap { storePhoto($0) }
    }

    private func deletePhoto(named name: String) {
        photoCache[name] = nil
        try? FileManager.default.removeItem(at: Self.photosDirectory().appendingPathComponent(name))
    }

    /// Deletes every photo file nothing in the wallet points to any more.
    ///
    /// `remove(_:)` deliberately leaves a removed card's photo file alone so
    /// Undo can put it back — this is where that file's debt finally comes
    /// due, once nothing could possibly still want it: after the undo window
    /// closes, or at the next launch if the app never got the chance to run
    /// that far.
    private func sweepOrphanedPhotos() {
        let directory = Self.photosDirectory()
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
        let inUse = Set(cards.compactMap(\.photoFilename))
        for file in files where !inUse.contains(file) {
            photoCache[file] = nil
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
        }
    }

    private static func photosDirectory() -> URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL.temporaryDirectory
        return base.appendingPathComponent("CardPhotos", isDirectory: true)
    }

    // MARK: - Persistence

    private static func defaultFileURL() -> URL {
        let directory = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL.temporaryDirectory
        return directory.appendingPathComponent("wallet.json")
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        cards = (try? decoder.decode([Card].self, from: data)) ?? []
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(cards) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}

extension WalletStore {
    /// A populated wallet for previews and for the workbench screen.
    static func previewStore() -> WalletStore {
        let store = WalletStore(fileURL: URL.temporaryDirectory.appendingPathComponent("preview-wallet.json"))
        if store.cards.isEmpty {
            for card in [
                CardCatalog.amexGold,
                CardCatalog.chaseFreedomFlex,
                CardCatalog.citiDoubleCash,
                CardCatalog.amexBlueCashPreferred,
                CardCatalog.chaseSapphirePreferred
            ] {
                store.add(card)
            }
        }
        return store
    }
}
