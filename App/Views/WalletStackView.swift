import SwiftUI
import CardKit

/// The home screen. Cards overlap so only the top strip of each shows; tapping
/// one expands it in place, and dragging one moves it in the stack. This is the
/// whole navigation — there is no tab bar.
struct WalletStackView: View {

    @Environment(WalletStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var expandedCardID: UUID?
    @State private var draggingCardID: UUID?
    @State private var dragTranslation: CGFloat = 0
    @State private var isAddingCard = false
    @State private var isShowingWorkbench = false

    @ScaledMetric(relativeTo: .title3) private var peekHeight: CGFloat = 88
    @ScaledMetric(relativeTo: .title3) private var cardHeight: CGFloat = 200

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
                ToolbarItem(placement: .topBarLeading) {
                    if !store.cards.isEmpty {
                        Button {
                            isShowingWorkbench = true
                        } label: {
                            Label("Try it", systemImage: "wand.and.stars")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isAddingCard = true
                    } label: {
                        Label("Add card", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $isAddingCard) {
                AddCardView()
            }
            .sheet(isPresented: $isShowingWorkbench) {
                EngineWorkbenchView()
            }
        }
    }

    // MARK: - The stack

    private var stack: some View {
        ScrollView {
            VStack(spacing: 0) {
                activationBanner

                ForEach(Array(store.cards.enumerated()), id: \.element.id) { index, card in
                    row(for: card, at: index)
                        .zIndex(zIndex(for: card, at: index))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, cardHeight - peekHeight + 32)
        }
        .scrollDismissesKeyboard(.immediately)
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
        .scaleEffect(isDragging ? 1.03 : 1.0)
        .animation(motion, value: expandedCardID)
        .animation(motion, value: store.cards.map(\.id))
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
                let target = index + slots
                withAnimation(motion) {
                    store.move(id: card.id, to: target)
                    draggingCardID = nil
                    dragTranslation = 0
                }
            }
    }

    /// Motion only in response to a user action, and none at all when the
    /// system asks for less.
    private var motion: Animation? {
        reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.82)
    }

    // MARK: - Copy

    /// The one thing this card is best at, shown on the visible top strip.
    private func highlight(for card: Card) -> String? {
        if let program = card.rotatingProgram,
           let quarter = program.quarter(Quarter.containing(Date())) {
            let rate = card.currency.formatted(rate: program.rate)
            let categories = quarter.categories.map(\.displayName).joined(separator: " · ")
            return quarter.isActivated
                ? "\(rate) \(categories) this quarter"
                : "Activate \(rate) \(categories)"
        }
        let best = card.rules
            .filter { $0.category != .base }
            .max { $0.rate < $1.rate }
        if let best {
            return "\(card.currency.formatted(rate: best.rate)) \(best.category.displayName.lowercased())"
        }
        if let base = card.rule(for: .base) {
            return "\(card.currency.formatted(rate: base.rate)) on everything"
        }
        return nil
    }

    @ViewBuilder
    private var activationBanner: some View {
        let pending = store.cardsNeedingActivation()
        if !pending.isEmpty {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "bell.badge.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(pending.count == 1
                         ? "\(pending[0].displayName) needs activating"
                         : "\(pending.count) cards need activating")
                        .font(.subheadline.weight(.semibold))
                    Text("A rotating bonus earns nothing until you click activate.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.bottom, 16)
        }
    }
}

#Preview {
    WalletStackView()
        .environment(WalletStore.previewStore())
}
