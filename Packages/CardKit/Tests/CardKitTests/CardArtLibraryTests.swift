import XCTest
@testable import CardKit

final class CardArtLibraryTests: XCTestCase {

    /// The whole point of the registry: nothing ships in it by default, so the
    /// app cannot be accidentally distributing issuer artwork.
    func testLibraryShipsEmpty() {
        XCTAssertTrue(
            CardArtLibrary.assets.isEmpty,
            "Artwork was added to the library. Every entry needs a licence you can produce on request — see docs/card-art.md."
        )
    }

    func testUserPhotoIsAlwaysAllowed() {
        XCTAssertTrue(ArtLicence.userPhoto.permitsDisplay)
        XCTAssertNil(ArtLicence.userPhoto.attribution, "The user's own card needs no credit line")
    }

    func testIssuerGrantCarriesAttribution() {
        let licence = ArtLicence.issuerProvided(source: "Example Bank", reference: "brand kit v3")
        XCTAssertTrue(licence.permitsDisplay)
        XCTAssertEqual(licence.attribution, "Artwork supplied by Example Bank (brand kit v3)")
    }

    /// A grant that has not been re-confirmed stops being drawn on its own,
    /// rather than quietly outliving the agreement.
    func testAssetStopsBeingUsableAfterItsReviewDate() {
        let asset = CardArtAsset(
            id: "example",
            issuer: "Example Bank",
            cardName: "Everyday",
            imageName: "example-everyday",
            licence: .affiliateProgramme(name: "Example Partners", termsURL: "https://example.com/terms"),
            reviewBy: Fixture.makeDate(2026, 1, 1)
        )
        XCTAssertTrue(asset.isUsable(asOf: Fixture.makeDate(2025, 12, 1)))
        XCTAssertFalse(asset.isUsable(asOf: Fixture.makeDate(2026, 6, 1)))
    }

    // MARK: - Resolution order

    func testFallsBackToDrawnWhenNothingIsLicensed() {
        let card = CardCatalog.amexGold
        XCTAssertEqual(CardArtSource.resolve(for: card), .drawn)
    }

    func testUserPhotoBeatsTheDrawnFinish() {
        var card = CardCatalog.amexGold
        card.photoFilename = "abc.jpg"
        XCTAssertEqual(CardArtSource.resolve(for: card), .userPhoto("abc.jpg"))
    }

    func testUnknownCardResolvesToDrawn() {
        var card = CardCatalog.citiDoubleCash
        card.issuer = "Some Bank We Have No Deal With"
        XCTAssertEqual(CardArtSource.resolve(for: card), .drawn)
    }
}
