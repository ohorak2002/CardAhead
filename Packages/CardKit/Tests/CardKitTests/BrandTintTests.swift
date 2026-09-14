import XCTest
@testable import CardKit

/// The test that would have caught an invisible icon.
///
/// The Card perks shield shipped at **1.05:1** against its own tile in dark
/// mode — present in the source, absent on the screen. Nobody spotted it in
/// review because there is nothing to spot: the line reads
/// `case .cardPerks: return Color(...)  // Navy`, which is exactly what it was
/// meant to say. It took a CI screenshot and a pixel measurement to find.
///
/// Screenshots are the right tool for *discovering* that class of bug and a
/// terrible one for *preventing* it — they need a macOS runner, seven minutes,
/// and a person to look at them. The numbers behind the colours are plain
/// data, so the same bug can be made impossible in a test that runs on any
/// machine in milliseconds. That is the only reason `BrandTint` lives in
/// CardKit rather than next to the SwiftUI that uses it.
final class BrandTintTests: XCTestCase {

    /// WCAG 1.4.11: a graphic that carries meaning needs 3:1 against what is
    /// behind it. Every icon in this app carries meaning — the colour is how a
    /// shelf is recognised before its label is read.
    private let minimumContrast = 3.0

    // MARK: - The arithmetic itself

    /// A contrast formula that is subtly wrong would pass everything below and
    /// prove nothing, so it gets pinned against the two ratios everybody knows.
    func testContrastRatioMatchesTheKnownAnchors() {
        XCTAssertEqual(TintRGB.black.contrastRatio(against: .white), 21.0, accuracy: 0.01)
        XCTAssertEqual(TintRGB.white.contrastRatio(against: .white), 1.0, accuracy: 0.001)
        // Symmetric: which one is "the background" must not change the answer.
        let blue = TintRGB(hex: 0x1E56D6)
        XCTAssertEqual(
            blue.contrastRatio(against: .white),
            TintRGB.white.contrastRatio(against: blue),
            accuracy: 0.0001
        )
    }

    /// The blend is what the screenshots actually show. Secondary Blue at 14%
    /// over white measured (223, 230, 249) in `4-benefits.png`; if this drifts,
    /// every threshold below is being measured against a fiction.
    func testWashBlendMatchesWhatTheScreenshotsShow() {
        let square = TintRGB(hex: 0x1E56D6).blended(alpha: 0.14, over: .white)
        XCTAssertEqual(square.red, 223, accuracy: 1)
        XCTAssertEqual(square.green, 231, accuracy: 1)
        XCTAssertEqual(square.blue, 249, accuracy: 1)
    }

    func testHexInitialiserReadsTheBrandSheetsNotation() {
        let navy = TintRGB(hex: 0x0B1F44)
        XCTAssertEqual(navy.red, 11)
        XCTAssertEqual(navy.green, 31)
        XCTAssertEqual(navy.blue, 68)
    }

    // MARK: - The bug this file exists for

    /// Every shelf, in both modes, as a glyph on its own 14% square.
    func testEveryShelfIsLegibleAgainstItsOwnIconSquare() {
        for group in BenefitGroup.allCases {
            for style in InterfaceStyle.allCases {
                let ratio = group.tintPalette.washContrast(for: style)
                XCTAssertGreaterThanOrEqual(
                    ratio, minimumContrast,
                    """
                    \(group.displayName) is \(String(format: "%.2f", ratio)):1 against its own \
                    icon square in \(style.rawValue) mode, under the 3:1 minimum. \
                    A colour this close to its background is not a quiet colour, it is an \
                    absent one — this is exactly how Card perks shipped at 1.05:1.
                    """
                )
            }
        }
    }

    /// The other role the same tints are used in: a solid map pin with a white
    /// symbol punched out of it.
    ///
    /// This half was failing before anybody looked — Groceries at 2.54:1,
    /// Entertainment at 2.49:1, Shopping at 2.80:1 — and it failed in *both*
    /// modes, because a pin is its own background and never adapted.
    func testEveryShelfIsLegibleUnderAWhiteGlyph() {
        for group in BenefitGroup.allCases {
            let ratio = group.tintPalette.solidContrast
            XCTAssertGreaterThanOrEqual(
                ratio, minimumContrast,
                """
                A white symbol on a solid \(group.displayName) pin is \
                \(String(format: "%.2f", ratio)):1, under the 3:1 minimum.
                """
            )
        }
    }

    /// `solid` must not quietly start following the interface style. A pin
    /// takes the darker value in both modes — see `BrandTint.solid`.
    func testASolidFillTakesTheDarkerValueInBothModes() {
        for group in BenefitGroup.allCases {
            XCTAssertEqual(
                group.tintPalette.solid, group.tintPalette.light,
                "\(group.displayName)'s pin colour should be its light-mode value in both modes."
            )
        }
    }

    // MARK: - Two colours that mean something else

    /// Drugstores used to be Error Red, saying "your best rate here is 3%" in
    /// the one colour this app reserves for things going wrong.
    func testNoShelfWearsTheErrorColour() {
        for group in BenefitGroup.allCases {
            for style in InterfaceStyle.allCases {
                XCTAssertNotEqual(
                    group.tintPalette.value(for: style), BrandChrome.error,
                    """
                    \(group.displayName) is Error Red in \(style.rawValue) mode. That colour is \
                    reserved for errors and destructive actions; a benefit shelf is good news.
                    """
                )
            }
        }
    }

    /// Primary Navy is the header gradient — the app's own frame. A shelf
    /// wearing it reads as "this is CardWise" rather than as a category, and
    /// at 1.05:1 on a dark tile it did not read as anything at all.
    func testNoShelfWearsTheHeaderNavy() {
        for group in BenefitGroup.allCases {
            for style in InterfaceStyle.allCases {
                XCTAssertNotEqual(
                    group.tintPalette.value(for: style), BrandChrome.navy,
                    "\(group.displayName) is Primary Navy in \(style.rawValue) mode, which is the header's colour."
                )
            }
        }
    }

    // MARK: - Coverage

    /// A shelf added later gets a palette entry or this fails — `tintPalette`
    /// switches exhaustively, so the compiler already enforces it, but a stray
    /// `default:` would silently hand every new shelf the same colour.
    func testEveryShelfHasItsOwnEntry() {
        let palettes = BenefitGroup.allCases.map(\.tintPalette)
        XCTAssertEqual(Set(palettes).count, BenefitGroup.allCases.count,
                       "Two shelves share a palette entry; a colour is how a shelf is told apart.")
    }

    /// A spending category never disagrees with the shelf it belongs to.
    func testASpendingCategoryBorrowsItsShelfsColour() {
        for category in SpendingCategory.allCases {
            XCTAssertEqual(
                category.tintPalette,
                BenefitGroup.containing(category).tintPalette
            )
        }
    }
}
