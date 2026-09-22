import SwiftUI
import CardKit

/// What a card earns, in one line, under the card itself.
///
/// **The wallet used to make you open a card to find out what it was for.**
/// It showed a fan of overlapping edges and a name; everything about *why you
/// carry this card* was one tap deeper. A wallet that cannot answer "what is
/// this one good for" without navigation is a list of pictures.
///
/// **Three at most, and the best three.** A premium card has a dozen earning
/// rules and printing all of them turns the wallet into the spreadsheet this
/// app exists to replace. Three is enough to characterise a card — the reason
/// you reach for it, plus the two that make it worth its fee — and the rest
/// are on the card's own screen.
///
/// **Derived, never stored.** `Card.benefits()` is the same list the Benefits
/// tab renders, read out of the rules the ranking engine already uses. A
/// second, prettier summary computed here would be free to drift from the one
/// that decides which card actually wins.
struct RewardSummary: View {
    let card: Card

    /// The rules the card earns by, best first, minus the ones that say
    /// nothing useful at a glance.
    ///
    /// **Rotating quarters are excluded on purpose.** A 5% category nobody has
    /// activated is not what this card earns, it is what it *could* earn, and
    /// the wallet is the wrong place to make that promise — Home's "worth
    /// doing" already chases it, with the deadline attached. Perks and signup
    /// bonuses are out for the same reason: they are not rates.
    private var top: [CardBenefit] {
        card.benefits()
            .filter { benefit in
                guard benefit.isActive else { return false }
                if case .rule = benefit.origin { return true }
                return false
            }
            .prefix(3)
            .map { $0 }
    }

    /// "2x points on everything" — the card's own words for its floor rate,
    /// formatted by the currency so a cash-back card says 2% and a points card
    /// says 2x.
    private var baseRateLine: String {
        let rate = card.currency.formatted(rate: card.baseRate)
        return "\(rate) \(card.currency.unitNoun) on everything"
    }

    var body: some View {
        if top.isEmpty {
            // A flat-rate card earns one thing everywhere, and a `.rule`
            // benefits are the exceptions to a base rate — so a card with no
            // exceptions genuinely has nothing to list here. Saying so is
            // better than an empty strip that looks like a failed load.
            Text(baseRateLine)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            // Wraps rather than scrolls. A horizontal scroller under every
            // card is three gesture surfaces stacked on one screen — the page
            // scrolls, the card drags to reorder, and now this — and the third
            // one is the one nobody expects.
            FlowRow(spacing: Metric.snug, rowSpacing: Metric.tight) {
                ForEach(top) { benefit in
                    HStack(spacing: 5) {
                        Image(systemName: benefit.group.symbolName)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(benefit.group.tint)
                        Text(benefit.title)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A row that wraps onto the next line instead of clipping or scrolling.
///
/// SwiftUI has no built-in for this and the usual workarounds are worse than
/// the layout: an `HStack` truncates, a `ScrollView` adds a gesture, and a
/// `LazyVGrid` forces equal columns that make "2x on everything else" and
/// "4x dining" the same width. A `Layout` measures each child and places it,
/// which is what is actually wanted.
///
/// Wrapping matters more than it sounds: at the accessibility text sizes
/// every one of these labels is two or three times wider, and a row that
/// cannot wrap is a row that loses its last item.
struct FlowRow: Layout {
    var spacing: CGFloat = 8
    var rowSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var widest: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: maxWidth.isFinite ? maxWidth : nil, height: nil))
            if x > 0, x + spacing + size.width > maxWidth {
                totalHeight += rowHeight + rowSpacing
                widest = max(widest, x)
                x = 0
                rowHeight = 0
            }
            x += (x > 0 ? spacing : 0) + size.width
            rowHeight = max(rowHeight, size.height)
        }
        widest = max(widest, x)
        totalHeight += rowHeight
        return CGSize(width: min(widest, maxWidth), height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            if x > bounds.minX, x + spacing + size.width > bounds.maxX {
                y += rowHeight + rowSpacing
                x = bounds.minX
                rowHeight = 0
            }
            if x > bounds.minX { x += spacing }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width
            rowHeight = max(rowHeight, size.height)
        }
    }
}
