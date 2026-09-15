import XCTest
@testable import CardKit

/// The material numbers, pinned.
///
/// Same reasoning as `BrandTintTests`: a `LinearGradient` is opaque until a
/// view renders it and somebody photographs the result, but the two doubles
/// behind it are not. These run on Linux in microseconds and catch the class of
/// mistake — a tweak that quietly inverts which surface is the shiny one — that
/// otherwise costs a macOS runner and a human squinting at a PNG.
final class CardFinishTests: XCTestCase {

    /// The invariant that makes materials read as materials.
    ///
    /// A hard, smooth surface reflects the light source nearly intact, so its
    /// highlight is **narrow**. A matte one scatters the same light into
    /// something wide and faint. Invert this and every card looks like the same
    /// plastic at a different exposure — which is exactly what the app looked
    /// like before `sheenSpread` existed.
    func testHarderSurfacesThrowTighterHighlights() {
        XCTAssertLessThan(CardFinish.glossy.sheenSpread, CardFinish.frosted.sheenSpread)
        XCTAssertLessThan(CardFinish.metal.sheenSpread, CardFinish.frosted.sheenSpread)
        XCTAssertLessThan(CardFinish.frosted.sheenSpread, CardFinish.matte.sheenSpread)
        XCTAssertLessThan(
            CardFinish.glossy.sheenSpread, CardFinish.matte.sheenSpread,
            "Gloss must be the tightest highlight of the four"
        )
    }

    /// And the brighter ones are the shinier ones.
    func testShinierSurfacesThrowStrongerHighlights() {
        XCTAssertGreaterThan(CardFinish.glossy.sheenOpacity, CardFinish.matte.sheenOpacity)
        XCTAssertGreaterThan(CardFinish.metal.sheenOpacity, CardFinish.frosted.sheenOpacity)
        XCTAssertLessThan(
            CardFinish.matte.sheenOpacity, CardFinish.frosted.sheenOpacity,
            "Matte is the flattest thing a card can be"
        )
    }

    /// The gradient the spread feeds has stops at `0.47 ± spread`, clamped into
    /// 0...1. A spread of zero collapses all three stops onto one another and
    /// the highlight vanishes; anything past 0.47 clamps, which silently moves
    /// the start of the band into the middle of the card. Neither is visible in
    /// a diff, and both are a one-character edit away.
    func testEverySpreadStaysInsideTheRangeTheGradientCanDraw() {
        for finish in CardFinish.allCases {
            XCTAssertGreaterThan(finish.sheenSpread, 0.02, "\(finish) has no highlight at all")
            XCTAssertLessThan(finish.sheenSpread, 0.47, "\(finish) clamps, which moves the band off centre")
            XCTAssertGreaterThan(finish.sheenOpacity, 0, "\(finish) is invisible")
            XCTAssertLessThan(finish.sheenOpacity, 0.6, "\(finish) washes the card out")
        }
    }

    /// Only metal is brushed. The brushing is drawn on top of the palette's own
    /// surface pattern, so turning it on for a second finish doubles the
    /// texture on that card rather than replacing it.
    func testOnlyMetalIsBrushed() {
        XCTAssertTrue(CardFinish.metal.isBrushed)
        for finish in CardFinish.allCases where finish != .metal {
            XCTAssertFalse(finish.isBrushed, "\(finish) is not a brushed material")
        }
    }

    /// A wallet written before finishes existed decodes with none, and matte is
    /// the honest default for a card whose material nobody ever stated.
    func testACardWithNoStatedMaterialIsMatte() {
        XCTAssertEqual(Card(issuer: "X", name: "Y").appearance, .matte)
    }

    func testEveryFinishHasAName() {
        for finish in CardFinish.allCases {
            XCTAssertFalse(finish.displayName.isEmpty)
        }
    }
}
