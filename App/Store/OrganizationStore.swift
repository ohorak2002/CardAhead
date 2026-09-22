import Foundation
import Observation
import CardKit

@Observable
@MainActor
final class OrganizationStore {
    private(set) var preferences = WalletOrganization()
    private(set) var failure: String?
    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private var canSave = true

    init(fileURL: URL? = nil) {
        let directory = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)) ?? .temporaryDirectory
        self.fileURL = fileURL ?? directory.appendingPathComponent("organization.json")
        guard FileManager.default.fileExists(atPath: self.fileURL.path) else { return }
        do {
            preferences = try JSONDecoder().decode(WalletOrganization.self, from: Data(contentsOf: self.fileURL))
        } catch {
            canSave = false
            failure = "Your wallet preferences could not be opened. The saved file has been kept."
        }
    }

    func name(for card: Card) -> String { preferences.name(for: card) }
    func isHidden(_ card: Card) -> Bool { preferences.hiddenCardIDs.contains(card.id) }
    func visibleCards(in cards: [Card]) -> [Card] { preferences.visibleCards(in: cards) }

    @discardableResult
    func update(_ change: (inout WalletOrganization) -> Void) -> Bool {
        guard canSave else { return false }
        var next = preferences
        change(&next)
        do {
            let data = try JSONEncoder().encode(next)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            preferences = next
            failure = nil
            return true
        } catch {
            failure = "Your changes could not be saved. Please try again."
            return false
        }
    }

    func erase() {
        canSave = true
        _ = update { $0 = WalletOrganization() }
    }
}
