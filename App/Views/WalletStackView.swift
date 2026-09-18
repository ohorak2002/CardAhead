import SwiftUI
import UIKit
import CardKit

/// Whole card faces with explicit expansion. Reordering lives in a native
/// list so a scroll on the wallet never accidentally changes its order.
struct WalletStackView: View {

    @Environment(WalletStore.self) private var store
    @Environment(ReminderCenter.self) private var reminders
    @Environment(ImpactStore.self) private var impact
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var expandedCardID: UUID?
    @State private var undone = Pulse()
    @State private var isAddingCard = false
    @State private var isReordering = false
    /// Measured, because a card cannot be sized any other way here. See
    /// `row(for:)`.
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

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "Wallet", subtitle: walletSubtitle) {
                HStack(spacing: Metric.tight) {
                    if store.cards.count > 1 {
                        HeaderButton(symbolName: "arrow.up.arrow.down", label: "Reorder cards") {
                            isReordering = true
                        }
                    }
                    HeaderButton(symbolName: "plus", label: "Add a card") {
                        isAddingCard = true
                    }
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
            .sheet(isPresented: $isReordering) { WalletReorderView() }
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
            .onChange(of: store.cards.map(\.id)) { _, ids in
                if let expandedCardID, !ids.contains(expandedCardID) {
                    self.expandedCardID = nil
                }
            }
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
                VStack(spacing: Metric.loose) {

                    ForEach(store.cards) { card in
                        row(for: card)
                            .id(card.id)
                            .zIndex(expandedCardID == card.id ? 1 : 0)
                    }

                    if remindersAreOff { locationRow }
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
                    if DemoSeed.requestedTab == "reorder" { isReordering = true }
                }
            }
            .onAppear { cardWidth = outer.size.width - Metric.margin * 2 }
            .onChange(of: outer.size.width) { _, width in
                cardWidth = width - Metric.margin * 2
            }
        }
    }

    private func row(for card: Card) -> some View {
        let isExpanded = expandedCardID == card.id
        return VStack(alignment: .leading, spacing: Metric.snug) {
            Button { toggle(card) } label: {
                VStack(alignment: .leading, spacing: Metric.tight) {
                    CardFaceView(card: card, photo: store.photo(for: card))
                        .frame(
                            width: cardWidth > 0 ? cardWidth : nil,
                            height: cardWidth > 0 ? cardWidth / 1.586 : nil
                        )
                    HStack(alignment: .top, spacing: Metric.snug) {
                        Text(card.displayName)
                            .font(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.cardWiseActionInk)
                    }
                    .foregroundStyle(.primary)
                    .frame(minHeight: Metric.minimumTarget, alignment: .center)
                    .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint(isExpanded ? "Double tap to hide details" : "Double tap to show details")

            if let status = highlight(for: card) {
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if isExpanded {
                CardDetailView(card: card)
                    .padding(.horizontal, Metric.regular)
                    .background(Color(.secondarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: Metric.tileRadius, style: .continuous))
                    .transition(.opacity)
            } else {
                RewardSummary(card: card)
            }
        }
        .animation(motion, value: expandedCardID)
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
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button("Undo") {
                undone.fire()
                withAnimation(motion) { store.undoRemove() }
            }
            .font(.subheadline.weight(.semibold))
            .frame(minWidth: Metric.minimumTarget, minHeight: Metric.minimumTarget)
        }
        .padding(13)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: Metric.tileRadius, style: .continuous))
        .padding(.horizontal, 20)
        .transition(.opacity)
        .accessibilityElement(children: .combine)
    }

    private func toggle(_ card: Card) {
        withAnimation(motion) {
            expandedCardID = expandedCardID == card.id ? nil : card.id
        }
    }

    private var motion: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.22)
    }

    // MARK: - Copy

    /// Quarter status is scalable text below the face, including on photos.
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

/// System reordering supplies autoscroll and drag cancellation. The menu and
/// VoiceOver actions use the same store operation for people who do not drag.
private struct WalletReorderView: View {
    @Environment(WalletStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(store.cards.enumerated()), id: \.element.id) { index, card in
                        HStack(spacing: Metric.snug) {
                            CardThumbnail(card: card, photo: store.photo(for: card), use: .walletDisplay)
                            Text(card.displayName)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            Menu {
                                moveActions(card, at: index)
                            } label: {
                                Image(systemName: "arrow.up.arrow.down")
                                    .frame(width: Metric.minimumTarget, height: Metric.minimumTarget)
                            }
                            .accessibilityLabel("Move \(card.displayName)")
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityValue("Position \(index + 1) of \(store.cards.count)")
                        .accessibilityActions { moveActions(card, at: index) }
                    }
                    .onMove { source, destination in
                        store.move(from: source, to: destination)
                    }
                } footer: {
                    Text("Drag a handle to reorder. You can also use the arrows to move a card one place at a time. Changes are saved as you go.")
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Reorder cards")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func moveActions(_ card: Card, at index: Int) -> some View {
        if index > 0 {
            Button("Move up") { store.move(id: card.id, to: index - 1) }
        }
        if index < store.cards.count - 1 {
            Button("Move down") { store.move(id: card.id, to: index + 1) }
        }
    }
}

#Preview {
    WalletStackView()
        .environment(WalletStore.previewStore())
        .environment(ReminderCenter())
        .environment(RegionMonitor())
        .environment(ImpactStore.previewStore())
}
