import SwiftUI

/// The panel that sits over the bottom of the map and can be pulled up.
///
/// **Not a `.sheet`, and the difference is the whole point.** A presented
/// sheet is modal: it covers the tab bar, it dims what is behind it, and
/// dismissing it is a gesture that means "go back". This is furniture — it is
/// always there, the map stays live and pannable behind it, and pulling it
/// down reveals more map rather than closing anything. That is the shape of
/// every map application people already know how to use, and a modal sheet
/// imitating it gets the feel wrong in a way nobody can name but everybody
/// notices.
///
/// **The drag lives on the grabber, not the whole panel.** A drag gesture over
/// the scrolling content has to fight the scroll view for every touch, and the
/// loser is whichever one the user wanted — you pull the sheet up and the list
/// scrolls instead. Restricting it to the handle makes the two gestures
/// unambiguous, at the cost of a slightly smaller target, which is why the
/// grabber's tappable area is much larger than the grey pill drawn in it.
struct CardWiseBottomSheet<Content: View>: View {

    @Binding var detent: CardWiseSheetDetent
    /// The height the sheet is measured against — the tab's, not the screen's.
    let availableHeight: CGFloat
    @ViewBuilder var content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drag: CGFloat = 0

    private var height: CGFloat {
        let resting = detent.height(in: availableHeight)
        let lowest = CardWiseSheetDetent.peek.height(in: availableHeight)
        let highest = CardWiseSheetDetent.tall.height(in: availableHeight)
        // Clamped rather than rubber-banded. Rubber-banding past the top of a
        // sheet that has a map above it just hides the map.
        return min(max(resting - drag, lowest), highest)
    }

    var body: some View {
        VStack(spacing: 0) {
            grabber
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(height: height, alignment: .top)
        .frame(maxWidth: .infinity)
        // `.regularMaterial`, so the map stays faintly visible through it and
        // the sheet reads as a layer over a place rather than a second screen.
        .background(.regularMaterial)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: Metric.cardRadius,
                topTrailingRadius: Metric.cardRadius,
                style: .continuous
            )
        )
        .shadow(color: Color.cardWiseNavy.opacity(0.18), radius: 20, y: -6)
        // Both branches spelled out as `Animation?`. A bare `nil` against a
        // leading-dot member in a ternary is exactly the shape that has failed
        // to type-check in this repo before — see the `Color`/`ShapeStyle`
        // bullet in CLAUDE.md.
        .animation(
            reduceMotion
                ? Animation?.none
                : Animation.spring(response: 0.34, dampingFraction: 0.86),
            value: detent
        )
    }

    private var grabber: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.secondary.opacity(0.35))
                .frame(width: 36, height: 5)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .padding(.bottom, Metric.snug)
        // The grey pill is 5 points tall; the thing you can grab is the full
        // width of the sheet and about 25 points of it.
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { drag = $0.translation.height }
                .onEnded { value in
                    // Where the finger was *going*, not where it stopped. A
                    // flick should throw the sheet to the next detent even
                    // though it only travelled twenty points.
                    let projected = detent.height(in: availableHeight) - value.predictedEndTranslation.height
                    drag = 0
                    detent = CardWiseSheetDetent.nearest(to: projected, in: availableHeight)
                }
        )
        .accessibilityElement()
        .accessibilityLabel("Resize the list")
        .accessibilityValue(detent.accessibilityName)
        // VoiceOver cannot drag, so the same three positions are adjustable.
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: detent = detent.taller
            case .decrement: detent = detent.shorter
            @unknown default: break
            }
        }
    }
}

/// The three heights the sheet rests at.
///
/// **Three, not a continuous height.** A sheet that stays wherever it was let
/// go looks flexible and is actually worse: it ends up at some arbitrary
/// height that shows two and a half rows, and every launch looks different.
/// Three positions mean three legible screens — the map, both, the list.
enum CardWiseSheetDetent: CaseIterable, Hashable {
    /// The map is the screen. Just the header of the list shows.
    case peek
    /// Both matter. The resting position, and where a selected place lands.
    case half
    /// The list is the screen, with a strip of map left as context.
    case tall

    func height(in available: CGFloat) -> CGFloat {
        switch self {
        // Enough for the grabber, the count and the sort control, and the top
        // edge of the first row — that last part on purpose, because a
        // cleanly cut-off list is what tells you it can be pulled up.
        case .peek: return min(158, available * 0.24)
        case .half: return available * 0.50
        case .tall: return available * 0.88
        }
    }

    static func nearest(to height: CGFloat, in available: CGFloat) -> CardWiseSheetDetent {
        allCases.min { one, two in
            abs(one.height(in: available) - height) < abs(two.height(in: available) - height)
        } ?? .half
    }

    var taller: CardWiseSheetDetent {
        switch self {
        case .peek: return .half
        case .half, .tall: return .tall
        }
    }

    var shorter: CardWiseSheetDetent {
        switch self {
        case .tall: return .half
        case .half, .peek: return .peek
        }
    }

    var accessibilityName: String {
        switch self {
        case .peek: return "Collapsed"
        case .half: return "Half open"
        case .tall: return "Open"
        }
    }
}
