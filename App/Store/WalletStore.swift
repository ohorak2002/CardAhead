import Foundation
import Observation
import SwiftUI
import UIKit
import CardKit

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

    private let fileURL: URL
    private let engine = RecommendationEngine()

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        load()
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

    func remove(_ card: Card) {
        if let name = card.photoFilename { deletePhoto(named: name) }
        cards.removeAll { $0.id == card.id }
        save()
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

    func setRotatingCapSpend(_ amount: Money, cardID: UUID) {
        update(cardID) { card in
            card.rotatingProgram?.cap?.spentDollars = amount
        }
    }

    func setPointValuation(_ centsPerUnit: Double, cardID: UUID) {
        update(cardID) { $0.currency.centsPerUnit = centsPerUnit }
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

    private func deletePhoto(named name: String) {
        photoCache[name] = nil
        try? FileManager.default.removeItem(at: Self.photosDirectory().appendingPathComponent(name))
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
