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
    @Environment(ReminderCenter.self) private var reminders
    @Environment(ImpactStore.self) private var impact
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var expandedCardID: UUID?
    @State private var draggingCardID: UUID?
    @State private var dragTranslation: CGFloat = 0
    @State private var isAddingCard = false
    /// Measured, because a card cannot be sized any other way here. See
    /// `row(for:at:)`.
    @State private var cardWidth: CGFloat = 0
    /// Set when somebody says yes to the follow-up, which is the only route to
    /// the one screen in this app that asks for a number.
    @State private var pricing: OpenRecommendation?

    @State private var locationAuth = LocationAuthorization()
    @State private var isShowingLocationPrimer = false
    /// Set when the wallet gains its first card, acted on once the add sheet
    /// has actually closed. Raising the primer while that sheet is still up
    /// asks iOS to stack a sheet on a sheet from the same view, which it
    /// quietly drops — losing the one permission the app cannot work without.
    @State private var shouldOfferPrimer = false
    /// Asked once, unprompted. After that the banner is the only reminder —
    /// a permission sheet that reappears on every launch is how apps get deleted.
    @AppStorage("hasOfferedLocationPrimer") private var hasOfferedLocationPrimer = false

    /// The peek has to clear the issuer, the card name *and* the highlight line.
    /// Cut it any shorter and the most useful line on the card hides behind the
    /// card below it.
    @ScaledMetric(relativeTo: .title3) private var peekHeight: CGFloat = 96
    /// 344pt wide at the real card ratio. Used only for the trailing gap under
    /// the last card — the card's own height comes from its aspect ratio.
    @ScaledMetric(relativeTo: .title3) private var cardHeight: CGFloat = 216

    var body: some View {
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
                // Both banners have to survive the wallet going empty — you
                // can remove your only card and still want it back.
                if store.lastRemoved != nil || impact.followUp != nil {
                    VStack(spacing: 10) {
                        if let removed = store.lastRemoved {
                            undoRemovedBanner(removed)
                                .padding(.top, 10)
                        }
                        // Transient, like the undo banner above it, and for
                        // the same reason it is allowed onto a screen that is
                        // otherwise only cards: it is about something that
                        // just happened, and it is gone as soon as it is
                        // answered or the day is over.
                        if let followUp = impact.followUp {
                            FollowUpPromptView(followUp: followUp) { answer in
                                answerFollowUp(followUp, with: answer)
                            }
                            .padding(.top, 10)
                        }
                    }
                    .animation(motion, value: store.lastRemoved)
                }
            }
            .sheet(isPresented: $isAddingCard, onDismiss: offerPrimerIfDue) {
                AddCardView()
            }
            .sheet(item: $pricing) { followUp in
                PurchaseAmountView(followUp: followUp) { amount in
                    impact.recordPurchase(amount, for: followUp.id)
                }
            }
            .sheet(isPresented: $isShowingLocationPrimer) {
                LocationPrimerView(auth: locationAuth) {
                    hasOfferedLocationPrimer = true
                }
            }
            // Asking on a cold launch means asking before there is a single
            // card to geofence. The first card is the moment the permission
            // starts meaning something, so that is when it gets asked for.
            .onChange(of: store.cards.count) { previous, current in
                guard previous == 0, current == 1,
                      !hasOfferedLocationPrimer,
                      remindersAreOff
                else { return }
                shouldOfferPrimer = true
            }
    }

    /// Yes opens the optional second question; everything else is the end of
    /// it. Nothing here is required of anybody — see `FollowUpPromptView`.
    private func answerFollowUp(_ followUp: OpenRecommendation, with answer: ImpactEventKind) {
        withAnimation(motion) {
            impact.recordAnswer(answer, for: followUp.id)
        }
        if answer == .recommendationAccepted {
            pricing = followUp
        }
    }

    /// Runs after the add sheet has gone, never while it is still there.
    private func offerPrimerIfDue() {
        guard shouldOfferPrimer else { return }
        shouldOfferPrimer = false
        isShowingLocationPrimer = true
    }

    /// The app cannot do its job without both permissions. Missing either one
    /// is the same outcome for the user — no reminder arrives — so it is the
    /// same banner.
    private var remindersAreOff: Bool {
        !locationAuth.hasAlways || !reminders.isAuthorized
    }

    /// A tap on a reminder should land on the card it named, open, not on a
    /// wallet the user then has to search.
    private func openCardFromReminder(_ id: UUID?, using proxy: ScrollViewProxy) {
        guard let id, store.card(withID: id) != nil else { return }
        withAnimation(motion) {
            expandedCardID = id
            proxy.scrollTo(id, anchor: .top)
        }
        reminders.cardToOpen = nil
    }

    // MARK: - The stack

    private var stack: some View {
        // **Measured from the container, not from the content.** The first
        // attempt put the GeometryReader behind the VStack, which is circular:
        // the VStack's width comes from its children, the children are sized
        // from the measurement, and the cards settled at whatever width the
        // longest line of text happened to want. The screen's width depends on
        // nothing inside it.
        GeometryReader { outer in
            ScrollViewReader { proxy in
                ScrollView {
                VStack(spacing: 0) {
                    if remindersAreOff { locationRow }

                    ForEach(Array(store.cards.enumerated()), id: \.element.id) { index, card in
                        row(for: card, at: index)
                            .id(card.id)
                            .zIndex(zIndex(for: card, at: index))
                    }

                    Text("Tap a card to open it. Drag one to move it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, cardHeight - peekHeight + 18)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Metric.margin)
                .padding(.top, Metric.tight)
                // Clear of the floating tab bar, which draws over the end of
                // any scroll view rather than shortening it.
                .padding(.bottom, 90)
                }
                // Both, because a tap on a reminder can either wake an app
                // that is already showing this screen or launch one that is
                // not, and the order those happen in is not ours to decide.
                .onChange(of: reminders.cardToOpen) { _, id in
                    openCardFromReminder(id, using: proxy)
                }
                .onAppear {
                    openCardFromReminder(reminders.cardToOpen, using: proxy)
                }
            }
            .onAppear { cardWidth = outer.size.width - Metric.margin * 2 }
            .onChange(of: outer.size.width) { _, width in
                cardWidth = width - Metric.margin * 2
            }
        }
    }

    private func row(for card: Card, at index: Int) -> some View {
        let isExpanded = expandedCardID == card.id
        let isDragging = draggingCardID == card.id

        return VStack(spacing: 0) {
            // **Explicitly sized, and it has to be.** `CardFaceView` sizes
            // itself with `aspectRatio(1.586, contentMode: .fit)`, and the
            // row's `frame(height: peekHeight)` below does not clip that — it
            // *proposes* 96pt, which an aspect-fit view answers by shrinking
            // to 152pt wide. Every card rendered at a third of the screen with
            // its own name truncated, and nobody could see it until CI started
            // taking screenshots. An explicit frame ignores the proposal, so
            // the card keeps its full width and the row still only advances
            // the layout by the peek — which is what makes the stack overlap.
            CardFaceView(
                card: card,
                highlight: highlight(for: card),
                photo: store.photo(for: card)
            )
                .frame(
                    width: cardWidth > 0 ? cardWidth : nil,
                    height: cardWidth > 0 ? cardWidth / 1.586 : nil
                )
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

    /// Shown only while the app cannot actually do its job. It is the one thing
    /// allowed to share the wallet screen with the cards, because without this
    /// permission every card on it is decoration.
    private var locationRow: some View {
        Button {
            isShowingLocationPrimer = true
        } label: {
            HStack(spacing: 11) {
                Image(systemName: "location.slash")
                    .foregroundStyle(Color.cardWiseWarning)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reminders are off")
                        .font(.subheadline.weight(.semibold))
                    Text(locationRowDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(13)
            .background(Color.cardWiseWarning.opacity(0.12), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.bottom, 14)
    }

    private var locationRowDetail: String {
        if !locationAuth.hasAlways {
            return locationAuth.isBlocked
                ? "iOS has already asked, so the switch lives in Settings now."
                : "Let us see where you are and we will name the card to use."
        }
        return reminders.isBlocked
            ? "We can see where you are, but notifications are switched off."
            : "We can see where you are. The reminder itself still needs a yes."
    }

    /// Removing a card asks no question first — see `WalletStore.remove(_:)`.
    /// This is the undo instead of the confirmation: it says what just
    /// happened and offers a few seconds to take it back, which is enough
    /// time to change your mind and not so much that it lingers as clutter.
    private func undoRemovedBanner(_ removed: RemovedCard) -> some View {
        HStack(spacing: 11) {
            Image(systemName: "trash")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Removed \(removed.card.displayName)")
                .font(.subheadline)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button("Undo") {
                withAnimation(motion) { store.undoRemove() }
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(13)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .padding(.horizontal, 20)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityElement(children: .combine)
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
        if let program = card.rotatingProgram {
            let rate = card.currency.formatted(rate: program.rate)
            switch program.status(for: Quarter.containing(Date())) {
            case .bonus(let quarter):
                let categories = quarter.categories
                    .map { $0.displayName.lowercased() }
                    .joined(separator: " and ")
                return quarter.isActivated
                    ? "\(rate) on \(categories) this quarter"
                    : "Switch on \(rate) for \(categories)"
            case .unannounced:
                // Said on the card face rather than in a banner, because it is
                // a fact about this card and not about the app.
                return "Nobody has published this quarter's \(rate) yet"
            case .none:
                break
            }
        }
        if let best = card.rules.filter({ $0.category != .base }).max(by: { $0.rate < $1.rate }) {
            // The shelf, not the raw category: `travelPortal` reads as "travel
            // booked through the issuer", which truncates on a card face and
            // is not how anybody describes their own card. Same reasoning as
            // `HomeView.bestFor`.
            let where_ = BenefitGroup.containing(best.category).displayName.lowercased()
            return "\(card.currency.formatted(rate: best.rate)) on \(where_)"
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
        .environment(ReminderCenter())
        .environment(RegionMonitor())
        .environment(ImpactStore.previewStore())
}
