import XCTest
@testable import CardKit

/// These tests are the interlock.
///
/// Every one of them asserts a *refusal* — and they all fail in the same
/// direction on purpose. If a rule below stops working, the app draws its own
/// card face, which is the worst thing that can happen here. Nothing in this
/// file may ever be written so that a mistake ends with issuer artwork on
/// screen instead.
final class CardArtLibraryTests: XCTestCase {

    // MARK: - Fixtures

    /// A grant in the state everything below varies from: approved, current,
    /// covering the wallet. The one shape that is allowed to draw.
    private func grant(
        productID: String = "amex-gold",
        version: String = "2026-01",
        status: ArtLicenceStatus = .approved,
        uses: Set<ArtUse> = [.walletDisplay, .appDisplay],
        effective: Date? = nil,
        expires: Date? = nil
    ) -> CardArtAsset {
        CardArtAsset(
            id: "\(productID)-\(version)",
            productID: productID,
            issuer: "Amex",
            cardName: "Gold",
            assetVersion: version,
            imageName: "amex-gold-2026",
            licence: .affiliateProgramme(name: "Example Partners", termsURL: "https://example.com/terms"),
            status: status,
            permittedUses: uses,
            effectiveDate: effective,
            expiresOn: expires
        )
    }

    private var today: Date { Fixture.makeDate(2026, 6, 1) }

    /// A catalog card, so it carries the product ID the lookup keys on.
    private func catalogCard(productID: String = "amex-gold") -> Card {
        var card = CardCatalog.amexGold
        card.catalogProductID = productID
        card.photoFilename = nil
        return card
    }

    // MARK: - The registry ships empty

    /// The whole point of the registry: nothing ships in it by default, so the
    /// app cannot be accidentally distributing issuer artwork. **This test
    /// failing is the feature** — it forces a deliberate decision rather than
    /// a quiet commit.
    func testLibraryShipsEmpty() {
        XCTAssertTrue(
            CardArtLibrary.assets.isEmpty,
            "Artwork was added to the library. Every entry needs a licence you can produce on request — see docs/card-art.md."
        )
    }

    func testNothingResolvesAsLicensedInTheShippingApp() {
        for entry in CardCatalog.entries {
            XCTAssertEqual(
                CardArtSource.resolve(for: entry.card), .drawn,
                "\(entry.productID) resolved to something other than the drawn face with an empty registry"
            )
        }
    }

    // MARK: - Resolution order (§47)

    func testLicensedAssetWins() {
        let source = CardArtSource.resolve(for: catalogCard(), in: [grant()], asOf: today)
        guard case .licensed(let asset) = source else {
            return XCTFail("An approved, current, wallet-covering grant should have been used")
        }
        XCTAssertEqual(asset.productID, "amex-gold")
    }

    func testLicensedAssetBeatsAUserPhoto() {
        var card = catalogCard()
        card.photoFilename = "mine.jpg"
        let source = CardArtSource.resolve(for: card, in: [grant()], asOf: today)
        guard case .licensed = source else {
            return XCTFail("Licensed artwork outranks the user's photo")
        }
    }

    func testUserPhotoBeatsTheDrawnFinish() {
        var card = catalogCard()
        card.photoFilename = "abc.jpg"
        XCTAssertEqual(CardArtSource.resolve(for: card, in: [], asOf: today), .userPhoto("abc.jpg"))
    }

    func testFallsBackToDrawnWhenNothingIsLicensed() {
        XCTAssertEqual(CardArtSource.resolve(for: catalogCard(), in: [], asOf: today), .drawn)
    }

    /// A wallet file can carry an empty string where a filename should be.
    /// Treating that as a photo puts an empty image slot on the card.
    func testEmptyPhotoFilenameIsNotAPhoto() {
        var card = catalogCard()
        card.photoFilename = ""
        XCTAssertEqual(CardArtSource.resolve(for: card, in: [], asOf: today), .drawn)
    }

    // MARK: - Licence safety (§48)

    func testMissingLicensedPixelsFallBackToDrawingEvenWithPhotoAvailable() {
        let selected = CardArtSource.resolve(for: catalogCard(), in: [grant()], asOf: today)
        let displayed = selected.availableForDisplay(licensedImageAvailable: false, photoAvailable: true)
        XCTAssertEqual(displayed, .drawn)
        XCTAssertEqual(displayed.shortLabel, "CardAhead representation")
        XCTAssertTrue(displayed.accessibilityDescription(for: catalogCard()).contains("CardAhead representation"))
    }

    func testLoadedLicensedPixelsKeepPriorityOverPhoto() {
        let selected = CardArtSource.resolve(for: catalogCard(), in: [grant()], asOf: today)
        XCTAssertEqual(selected.availableForDisplay(licensedImageAvailable: true, photoAvailable: true), selected)
    }

    func testMissingPhotoPixelsAreDescribedAsDrawn() {
        let selected = CardArtSource.userPhoto("deleted.jpg")
        XCTAssertEqual(selected.availableForDisplay(licensedImageAvailable: false, photoAvailable: false), .drawn)
        XCTAssertEqual(selected.availableForDisplay(licensedImageAvailable: false, photoAvailable: true), selected)
    }

    func testUnsavedPhotoPreviewUsesPhotoProvenance() {
        let displayed = CardArtSource.drawn.availableForDisplay(licensedImageAvailable: false, photoAvailable: true)
        XCTAssertEqual(displayed, .userPhoto(""))
        XCTAssertEqual(displayed.shortLabel, "Your card photo")
    }

    func testAvailablePixelsCannotPromoteARefusedGrant() {
        let selected = CardArtSource.resolve(for: catalogCard(), in: [grant(status: .revoked)], asOf: today)
        XCTAssertEqual(selected.availableForDisplay(licensedImageAvailable: true, photoAvailable: false), .drawn)
    }

    func testWalletOnlyGrantDoesNotReachAppDisplay() {
        let selected = CardArtSource.resolve(for: catalogCard(), in: [grant(uses: [.walletDisplay])], use: .appDisplay, asOf: today)
        XCTAssertEqual(selected, .drawn)
    }

    func testPendingGrantCannotDraw() {
        let asset = grant(status: .pendingReview)
        XCTAssertFalse(asset.isUsable(asOf: today))
        XCTAssertEqual(
            CardArtSource.resolve(for: catalogCard(), in: [asset], asOf: today), .drawn,
            "A grant still being negotiated must never reach the screen"
        )
    }

    func testRevokedGrantCannotDraw() {
        let asset = grant(status: .revoked)
        XCTAssertFalse(asset.isUsable(asOf: today))
        XCTAssertEqual(CardArtSource.resolve(for: catalogCard(), in: [asset], asOf: today), .drawn)
    }

    func testExpiredGrantCannotDraw() {
        let asset = grant(expires: Fixture.makeDate(2026, 1, 1))
        XCTAssertTrue(asset.isUsable(asOf: Fixture.makeDate(2025, 12, 1)), "Still inside the grant")
        XCTAssertFalse(asset.isUsable(asOf: today), "Past it")
        XCTAssertEqual(CardArtSource.resolve(for: catalogCard(), in: [asset], asOf: today), .drawn)
    }

    /// An asset already in the app bundle is not permission to show it. The
    /// grant's start date is the permission.
    func testGrantThatHasNotStartedYetCannotDraw() {
        let asset = grant(effective: Fixture.makeDate(2026, 9, 1))
        XCTAssertFalse(asset.isUsable(asOf: today))
        XCTAssertTrue(asset.isUsable(asOf: Fixture.makeDate(2026, 10, 1)))
    }

    /// The separation that matters most in practice: brand kits routinely
    /// permit one of these and withhold the other.
    func testMarketingOnlyGrantCannotBeUsedInTheWallet() {
        let asset = grant(uses: [.marketing, .appStore])
        XCTAssertFalse(asset.isUsable(for: .walletDisplay, asOf: today))
        XCTAssertFalse(asset.isUsable(for: .appDisplay, asOf: today))
        XCTAssertTrue(asset.isUsable(for: .marketing, asOf: today))
        XCTAssertEqual(CardArtSource.resolve(for: catalogCard(), in: [asset], asOf: today), .drawn)
    }

    func testInAppGrantDoesNotImplyMarketingRights() {
        let asset = grant(uses: [.walletDisplay, .appDisplay])
        XCTAssertTrue(asset.isUsable(for: .walletDisplay, asOf: today))
        XCTAssertFalse(
            asset.isUsable(for: .marketing, asOf: today),
            "Permission to draw it in the app is not permission to put it on a website"
        )
        XCTAssertFalse(
            asset.isUsable(for: .appStore, asOf: today),
            "App Store screenshots are the most commonly withheld use of the four"
        )
    }

    func testGrantWithNoStatedUsesCannotDraw() {
        XCTAssertFalse(grant(uses: []).isUsable(asOf: today))
    }

    // MARK: - Keyed on the product, not on two display strings (§11, §12)

    /// The bug this replaces: matching on issuer and name meant a card someone
    /// typed in by hand as "Amex"/"Gold" picked up artwork granted for the
    /// catalog product, and an issuer renaming a card silently lost it.
    func testCardTypedInByHandNeverMatchesAGrant() {
        var handTyped = Card(issuer: "Amex", name: "Gold")
        handTyped.catalogProductID = nil
        XCTAssertNil(CardArtLibrary.asset(for: handTyped))
        XCTAssertEqual(CardArtSource.resolve(for: handTyped, in: [grant()], asOf: today), .drawn)
    }

    func testRenamingTheCardDoesNotLoseItsArtwork() {
        var card = catalogCard()
        card.issuer = "American Express"
        card.name = "Gold Card"
        guard case .licensed = CardArtSource.resolve(for: card, in: [grant()], asOf: today) else {
            return XCTFail("The product ID, not the display name, is the key")
        }
    }

    func testAGrantForOneProductDoesNotCoverAnother() {
        let card = catalogCard(productID: "amex-platinum")
        XCTAssertEqual(CardArtSource.resolve(for: card, in: [grant(productID: "amex-gold")], asOf: today), .drawn)
    }

    // MARK: - Versioning (§13)

    /// Issuers redesign. Both printings can be licensed at once; the later one
    /// is the card in people's hands.
    func testNewestLicensedVersionWins() {
        let old = grant(version: "2023-04")
        let new = grant(version: "2026-01")
        let found = CardArtLibrary.match(productID: "amex-gold", in: [old, new], asOf: today)
        XCTAssertEqual(found?.assetVersion, "2026-01")
    }

    /// A redesign whose grant has not come through yet must not drag the old,
    /// still-licensed face down with it.
    func testAnUnapprovedRedesignFallsBackToTheLicensedOlderVersion() {
        let old = grant(version: "2023-04")
        let new = grant(version: "2026-01", status: .pendingReview)
        let found = CardArtLibrary.match(productID: "amex-gold", in: [old, new], asOf: today)
        XCTAssertEqual(found?.assetVersion, "2023-04")
    }

    // MARK: - Manifest decoding (§27, §48)

    private func manifest(_ json: String) -> CardArtAsset? {
        CardArtAsset.fromManifest(Data(json.utf8))
    }

    func testAWellFormedManifestDecodes() {
        let asset = manifest("""
        {
          "id": "example-everyday-2026",
          "productID": "example-everyday",
          "issuer": "Example Bank",
          "cardName": "Everyday",
          "assetVersion": "2026-01",
          "imageName": "example-everyday",
          "licence": { "affiliateProgramme": { "name": "Example Partners", "termsURL": "https://example.com/terms" } },
          "status": "approved",
          "permittedUses": ["walletDisplay"],
          "effectiveDate": "2026-01-01T00:00:00Z",
          "expiresOn": "2027-01-01T00:00:00Z",
          "modificationAllowed": false,
          "croppingAllowed": true
        }
        """)
        XCTAssertEqual(asset?.productID, "example-everyday")
        XCTAssertEqual(asset?.status, .approved)
        XCTAssertEqual(asset?.permittedUses, Set<ArtUse>([.walletDisplay]))
        XCTAssertEqual(asset?.croppingAllowed, true)
        XCTAssertEqual(asset?.modificationAllowed, false)
        XCTAssertTrue(asset?.isUsable(asOf: today) == true)
    }

    /// The single most important line in this file. A manifest that forgot to
    /// say must not read as a grant.
    func testAManifestMissingItsStatusIsPendingNotApproved() {
        let asset = manifest("""
        {
          "id": "x", "productID": "x", "issuer": "X", "cardName": "X", "imageName": "x",
          "licence": { "userPhoto": {} },
          "permittedUses": ["walletDisplay"]
        }
        """)
        XCTAssertEqual(asset?.status, .pendingReview)
        XCTAssertFalse(asset?.isUsable(asOf: today) ?? true)
    }

    func testAManifestMissingItsUsesGrantsNone() {
        let asset = manifest("""
        {
          "id": "x", "productID": "x", "issuer": "X", "cardName": "X", "imageName": "x",
          "licence": { "userPhoto": {} },
          "status": "approved"
        }
        """)
        XCTAssertEqual(asset?.permittedUses, Set<ArtUse>())
        XCTAssertFalse(asset?.isUsable(asOf: today) ?? true, "Approved for nothing in particular is approved for nothing")
    }

    /// Modification and cropping default to no, so a grant that is silent about
    /// them is not read as permitting them.
    func testModificationAndCroppingDefaultToRefused() {
        let asset = manifest("""
        {
          "id": "x", "productID": "x", "issuer": "X", "cardName": "X", "imageName": "x",
          "licence": { "userPhoto": {} }, "status": "approved"
        }
        """)
        XCTAssertEqual(asset?.modificationAllowed, false)
        XCTAssertEqual(asset?.croppingAllowed, false)
        XCTAssertEqual(asset?.attributionRequired, true, "Crediting by default is simpler than tracking which grants demand it")
    }

    func testBrokenManifestIsRefusedRatherThanCrashing() {
        XCTAssertNil(manifest("{ not json"))
        XCTAssertNil(manifest("{}"), "No id, no product, no licence — nothing to trust")
        XCTAssertNil(
            manifest("""
            {
              "id": "x", "productID": "x", "issuer": "X", "cardName": "X", "imageName": "x",
              "licence": { "userPhoto": {} }, "status": "approved-ish"
            }
            """),
            "A status nobody defined is not a status"
        )
    }

    // MARK: - Audit and attribution

    func testAttributionsOnlyCoverArtworkActuallyOnScreen() {
        XCTAssertTrue(
            CardArtLibrary.attributions().isEmpty,
            "An empty registry credits nobody"
        )
    }

    func testRevokedAssetReportsWhyItIsBlocked() {
        XCTAssertEqual(grant(status: .revoked).blockingReason(asOf: today), "Grant was withdrawn")
        XCTAssertEqual(grant(status: .pendingReview).blockingReason(asOf: today), "Grant not confirmed yet")
        XCTAssertEqual(
            grant(expires: Fixture.makeDate(2026, 1, 1)).blockingReason(asOf: today),
            "Grant lapsed and needs re-confirming"
        )
        XCTAssertEqual(
            grant(uses: [.marketing]).blockingReason(for: .walletDisplay, asOf: today),
            "Grant does not cover showing it in the wallet"
        )
        XCTAssertNil(grant().blockingReason(asOf: today), "A live grant is not blocked")
    }

    // MARK: - What the app is allowed to say (§24)

    /// The drawn face must never be described as the bank's.
    func testTheDrawnFaceIsNeverDescribedAsOfficial() {
        let line = CardArtSource.drawn.provenanceLine.lowercased()
        XCTAssertTrue(line.contains("cardahead"))
        for word in ["official", "authentic", "exact", "genuine", "issued by"] {
            XCTAssertFalse(line.contains(word), "The drawn face described itself as \"\(word)\"")
        }
        XCTAssertTrue(line.contains("not the bank's artwork"), "It has to say so, not merely avoid saying otherwise")
        XCTAssertEqual(CardArtSource.drawn.shortLabel, "CardAhead representation")
        XCTAssertEqual(CardArtSource.userPhoto("x.jpg").shortLabel, "Your card photo")
    }

    /// VoiceOver has to be told which of the three it is looking at, because
    /// the difference is invisible to it otherwise.
    func testAccessibilityDescriptionNamesTheSource() {
        let card = catalogCard()
        XCTAssertEqual(
            CardArtSource.drawn.accessibilityDescription(for: card),
            "CardAhead representation of Amex Gold"
        )
        XCTAssertEqual(
            CardArtSource.userPhoto("x.jpg").accessibilityDescription(for: card),
            "Photo of your Amex Gold card"
        )
        XCTAssertEqual(
            CardArtSource.licensed(grant()).accessibilityDescription(for: card),
            "Amex Gold card"
        )
    }

    // MARK: - The licence value itself

    func testUserPhotoNeedsNoCreditLine() {
        XCTAssertNil(ArtLicence.userPhoto.attribution, "The user's own card needs no credit")
    }

    func testIssuerGrantCarriesAttribution() {
        let licence = ArtLicence.issuerProvided(source: "Example Bank", reference: "brand kit v3")
        XCTAssertEqual(licence.attribution, "Artwork supplied by Example Bank (brand kit v3)")
        XCTAssertEqual(licence.reference, "Example Bank — brand kit v3")
    }

    /// Provenance is not permission. An asset the issuer definitely sent us is
    /// still refused while the paperwork says pending — which is the case that
    /// would otherwise feel safe enough to wave through.
    func testProvenanceAloneIsNotPermission() {
        var asset = grant(status: .pendingReview)
        asset.licence = .issuerProvided(source: "Amex", reference: "email 2026-05-02")
        XCTAssertFalse(asset.isUsable(asOf: today))
    }
}
