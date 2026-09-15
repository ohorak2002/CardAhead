import SwiftUI
import UIKit
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
    /// A card leaving the stack under your thumb, and landing again. These are
    /// the two moments in the app where something physical happens and your
    /// own hand is covering it — which is the whole argument for a haptic.
    @State private var lifted = Pulse()
    @State private var dropped = Pulse()
    /// Getting a card back. `.success` rather than an impact, because an undo
    /// is a recovery and that is what the success pattern means.
    @State private var undone = Pulse()
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
    /// 344pt wide at the real card ratio — the fallback height before the
    /// first layout has measured the screen.
    @ScaledMetric(relativeTo: .title3) private var cardHeight: CGFloat = 216
    /// Roughly how tall one whole row is: the card face at its real ratio,
    /// its reward summary, and the gap to the next one.
    ///
    /// **Only the drag gesture uses this, and only to count slots.** It is
    /// deliberately approximate: `move(id:to:)` clamps to the ends of the
    /// wallet, and the result is rounded, so being a few points out moves a
    /// card by the same number of places it would have anyway. Measuring it
    /// exactly would mean a `GeometryReader` per row to make a rounding
    /// operation marginally more precise.
    private var rowPitch: CGFloat {
        let face = cardWidth > 0 ? cardWidth / 1.586 : cardHeight
        return face + summaryHeight + Metric.roomy
    }
    /// The reward line under a card. One line of footnote plus its padding.
    @ScaledMetric(relativeTo: .footnote) private var summaryHeight: CGFloat = 40

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "Wallet", subtitle: walletSubtitle) {
                HeaderButton(symbolName: "plus", label: "Add a card") {
                    isAddingCard = true
                }
            }
            Group {
                if store.cards.isEmpty {
                    EmptyStateView { isAddingCard = true }
                } else {
                    stack
                }
            }
            }
            .background(Color(.systemGroupedBackground))
            .toolbar(.hidden, for: .navigationBar)
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
            // Light on the way up, firmer on the way down — the weight of a
            // thing being picked up and then set down. Same pairing the system
            // uses for its own drag-to-reorder.
            .sensoryFeedback(.impact(weight: .light), trigger: lifted)
            .sensoryFeedback(.impact(weight: .medium), trigger: dropped)
            .sensoryFeedback(.success, trigger: undone)
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

    /// "3 cards · 12 active benefits", or nothing at all when the wallet is
    /// empty and there is no count worth printing.
    private var walletSubtitle: String? {
        guard !store.cards.isEmpty else { return nil }
        let cards = store.cards.count == 1 ? "1 card" : "\(store.cards.count) cards"
        let active = WalletInsights.activeBenefitCount(in: store.cards)
        guard active > 0 else { return cards }
        let benefits = active == 1 ? "1 active benefit" : "\(active) active benefits"
        return "\(cards) · \(benefits)"
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
                // **The stack is gone and that is the point.** Cards used
                // to overlap, showing 96 points of each — a fan of coloured
                // edges with one whole card at the bottom. It was compact and
                // it meant you could not actually look at your cards, which
                // is the one thing a wallet is for. Each card is now whole,
                // with what it earns underneath it.
                VStack(spacing: Metric.roomy) {
                    if remindersAreOff { locationRow }

                    ForEach(Array(store.cards.enumerated()), id: \.element.id) { index, card in
                        row(for: card, at: index)
                            .id(card.id)
                            .zIndex(zIndex(for: card, at: index))
                    }

                    Text("Tap a card to open it. Drag one to move it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, Metric.tight)
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
                    // The expanded card is a tap away, and `simctl` cannot
                    // tap — so without this the card detail would be the one
                    // screen in the app nobody had ever seen. Same arrangement
                    // as the map's two place surfaces. Nil in any real build.
                    if DemoSeed.requestedTab == "carddetail", expandedCardID == nil {
                        expandedCardID = store.cards.first?.id
                    }
                    // The add-card sheet is behind the plus button, which
                    // `simctl` cannot press either.
                    if DemoSeed.requestedTab == "addcard" { isAddingCard = true }
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
            // **Explicitly sized, and it still has to be even without the
            // stack.** `CardFaceView` sizes itself with
            // `aspectRatio(1.586, contentMode: .fit)`, which answers a short
            // height proposal by shrinking its *width* — that is how every
            // card once rendered at a third of the screen with its own name
            // truncated, invisible until CI started taking screenshots. An
            // explicit frame ignores the proposal, so the card keeps its full
            // width. The row no longer advances by a peek, but the reason the
            // frame exists is unchanged and it must not be removed
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

            // **The summary is what a *closed* card says.** Open, it was the
            // same three rules printed twice a hundred points apart — once
            // here with icons, once under "Dining" and "Groceries" in the
            // detail's own list. The detail supersedes it rather than
            // repeating it.
            if !isExpanded {
                RewardSummary(card: card)
                    .padding(.top, Metric.snug)
            } else {
                CardDetailView(card: card)
                    .transition(.opacity)
            }
        }
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
                undone.fire()
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
                // The first frame of a drag is the card coming off the stack.
                // Firing here rather than in `updating` keeps it to once per
                // drag: `onChanged` runs on every frame, and this is the only
                // frame where nothing was being dragged a moment ago.
                if draggingCardID != card.id { lifted.fire() }
                draggingCardID = card.id
                dragTranslation = value.translation.height
            }
            .onEnded { value in
                guard draggingCardID == card.id else { return }
                // **`predictedEndTranslation`, not `translation`.** Where the
                // finger stopped is not where the card should go: a flick has
                // momentum, and a stack that ignored it made a quick throw and
                // a slow shove of the same length do the same thing, which is
                // the single clearest way an iOS gesture can feel dead.
                // `predictedEndTranslation` is where the drag would have come
                // to rest given the speed it ended at, which is the same
                // number the system's own scroll views settle on.
                //
                // Overshoot costs nothing here: `WalletStore.move(id:to:)`
                // clamps to the ends of the wallet, so the worst a hard flick
                // can do is send the card to the top or the bottom — which is
                // exactly what a hard flick should do.
                let slots = Int((value.predictedEndTranslation.height / rowPitch).rounded())
                dropped.fire()
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
        // **Nothing else goes on the face any more.** This used to fall
        // through to the card's best rate, and then to its base rate — which
        // `RewardSummary` now prints directly under the card, in full. The
        // screenshot showed the cost: a face reading "5x on travel" above a
        // line reading "5x on travel booked through the issuer", which is the
        // same fact twice, the second time more accurately.
        //
        // The rotating cases above survive because they are the one thing the
        // summary deliberately leaves out: a quarter nobody has switched on is
        // a *status*, not a rate, and it belongs where the card is.
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
