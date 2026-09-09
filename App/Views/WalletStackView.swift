import SwiftUI
import CardKit

/// The home screen, and deliberately the only thing on it: the cards, and a way
/// to add one. Cards overlap so only the top strip of each shows, tapping one
/// expands it in place, and dragging one moves it in the stack.
///
/// Everything that is not a card — what each card would earn, the reasoning,
/// the caveats — is one tap away on `WhyThisCardView`. A phone screen holding
/// two subjects at once is a phone screen nobody reads.
struct WalletStackView: View {

    @Environment(WalletStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var expandedCardID: UUID?
    @State private var draggingCardID: UUID?
    @State private var dragTranslation: CGFloat = 0
    @State private var isAddingCard = false

    /// The peek has to clear the issuer, the card name *and* the highlight line.
    /// Cut it any shorter and the most useful line on the card hides behind the
    /// card below it.
    @ScaledMetric(relativeTo: .title3) private var peekHeight: CGFloat = 96
    @ScaledMetric(relativeTo: .title3) private var cardHeight: CGFloat = 172

    var body: some View {
        NavigationStack {
            Group {
                if store.cards.isEmpty {
                    EmptyStateView { isAddingCard = true }
                } else {
                    stack
                }
            }
            .navigationTitle("Wallet")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isAddingCard = true
                    } label: {
                        Label("Add a card", systemImage: "plus")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !store.cards.isEmpty { whyBar }
            }
            .sheet(isPresented: $isAddingCard) {
                AddCardView()
            }
        }
    }

    // MARK: - The stack

    private var stack: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(store.cards.enumerated()), id: \.element.id) { index, card in
                    row(for: card, at: index)
                        .zIndex(zIndex(for: card, at: index))
                }

                Text("Tap a card to open it. Drag one to move it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, cardHeight - peekHeight + 18)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
    }

    private func row(for card: Card, at index: Int) -> some View {
        let isExpanded = expandedCardID == card.id
        let isDragging = draggingCardID == card.id

        return VStack(spacing: 0) {
            CardFaceView(card: card, highlight: highlight(for: card))
                .frame(height: cardHeight)
                .contentShape(Rectangle())
                .onTapGesture { toggle(card) }
                .gesture(dragGesture(for: card, at: index))

            if isExpanded {
                CardDetailView(card: card)
                    .transition(.opacity)
            }
        }
        .frame(height: isExpanded ? nil : peekHeight, alignment: .top)
        .offset(y: isDragging ? dragTranslation : 0)
        .scaleEffect(isDragging ? 1.04 : 1.0)
        // A dragged card tilts the way a real one would if you picked it out of
        // a stack. Small, capped, and only while a finger is on it.
        .rotationEffect(.degrees(isDragging ? tilt : 0))
        .animation(motion, value: expandedCardID)
        .animation(motion, value: store.cards.map(\.id))
        .animation(lift, value: isDragging)
    }

    private var whyBar: some View {
        NavigationLink {
            WhyThisCardView()
        } label: {
            HStack {
                Text("Why this card")
                    .font(.body.weight(.semibold))
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 15)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(.bar)
    }

    private func zIndex(for card: Card, at index: Int) -> Double {
        if draggingCardID == card.id { return 10_000 }
        if expandedCardID == card.id { return 9_000 }
        // Later cards sit on top of earlier ones, which is what makes the overlap read.
        return Double(index)
    }

    // MARK: - Gestures

    private func toggle(_ card: Card) {
        withAnimation(motion) {
            expandedCardID = (expandedCardID == card.id) ? nil : card.id
        }
    }

    private func dragGesture(for card: Card, at index: Int) -> some Gesture {
        DragGesture(minimumDistance: 14)
            .onChanged { value in
                guard expandedCardID == nil else { return }
                draggingCardID = card.id
                dragTranslation = value.translation.height
            }
            .onEnded { value in
                guard draggingCardID == card.id else { return }
                let slots = Int((value.translation.height / peekHeight).rounded())
                withAnimation(motion) {
                    store.move(id: card.id, to: index + slots)
                    draggingCardID = nil
                    dragTranslation = 0
                }
            }
    }

    /// Capped so a long drag does not spin the card.
    private var tilt: Double {
        max(-2.5, min(2.5, dragTranslation / 42))
    }

    /// Motion only in response to a user action, and none at all when the
    /// system asks for less.
    private var motion: Animation? {
        reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.78)
    }

    /// Picking a card up and putting it down wants to be snappier than a reorder.
    private var lift: Animation? {
        reduceMotion ? nil : .spring(response: 0.26, dampingFraction: 0.7)
    }

    // MARK: - Copy

    /// The one thing this card is best at, shown on the visible top strip.
    private func highlight(for card: Card) -> String? {
        if let program = card.rotatingProgram,
           let quarter = program.quarter(Quarter.containing(Date())) {
            let rate = card.currency.formatted(rate: program.rate)
            let categories = quarter.categories
                .map { $0.displayName.lowercased() }
                .joined(separator: " and ")
            return quarter.isActivated
                ? "\(rate) on \(categories) this quarter"
                : "Switch on \(rate) for \(categories)"
        }
        if let best = card.rules.filter({ $0.category != .base }).max(by: { $0.rate < $1.rate }) {
            return "\(card.currency.formatted(rate: best.rate)) on \(best.category.displayName.lowercased())"
        }
        if let base = card.rule(for: .base) {
            return "\(card.currency.formatted(rate: base.rate)) on everything"
        }
        return nil
    }
}

#Preview {
    WalletStackView()
        .environment(WalletStore.previewStore())
}
