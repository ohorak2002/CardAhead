import SwiftUI
import CardKit

/// The third and last screen.
///
/// Deliberately short. Everything here either changes what the app recommends
/// or answers a question the user is entitled to ask about their own data.
/// Controls for features that do not exist yet are not settings, they are
/// furniture — so reminder limits arrive with the reminders, not before.
struct SettingsView: View {

    @Environment(WalletStore.self) private var store
    @Environment(RegionMonitor.self) private var monitor
    @Environment(ReminderCenter.self) private var reminders
    @Environment(ImpactStore.self) private var impact
    @Environment(NotificationPolicyStore.self) private var notifications
    @Environment(OrganizationStore.self) private var organization
    let auth: LocationAuthorization

    @AppStorage("preferredName") private var preferredName = ""
    @State private var isConfirmingErase = false
    /// A heavy impact, not `.success`. Wiping everything is the thing the user
    /// asked for, twice, so it is not a warning either — but a bright little
    /// success chime for deleting your own data reads as the app being pleased
    /// about it. A weighty, neutral thud is what that moment sounds like.
    @State private var erased = Pulse()
    @State private var isShowingArtworkDetail = false

    /// **No Map section, on purpose.** Its one row only ever changed the map,
    /// so it now lives on the map, beside the Filters button. A settings list
    /// earns a section by holding something with nowhere better to be.
    var body: some View {
        List {
            nameSection
            valuationSection
            remindersSection
            activitySection
            artworkSection
            dataSection
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.impact(weight: .heavy), trigger: erased)
        .sheet(isPresented: $isShowingArtworkDetail) {
            CardArtworkExplainerView()
        }
        .alert("Erase everything?", isPresented: $isConfirmingErase) {
            Button("Cancel", role: .cancel) {}
            Button("Erase", role: .destructive) {
                erased.fire()
                store.eraseEverything()
                impact.erase()
                organization.erase()
            }
        } message: {
            Text("Removes every card, every photo, and the record of what these reminders earned you. Local deletion cannot be undone. Shared Impact deletion is also requested; reconnect while signed in to complete it. Your optional sign-in account remains.")
        }
    }

    // MARK: - What to call you

    /// Asked for nowhere else, and the app works perfectly without it. A
    /// greeting is worth having and not worth an onboarding step.
    private var nameSection: some View {
        Section {
            TextField("Your name", text: $preferredName)
                .textContentType(.givenName)
                .autocorrectionDisabled()
        } header: {
            Text("Greeting").textCase(nil)
        } footer: {
            Text("Only used to say hello on the home screen. Leave it blank and it just says good morning.")
        }
    }

    // MARK: - What a point is worth

    @ViewBuilder
    private var valuationSection: some View {
        let currencies = store.valuablePointCurrencies
        Section {
            if currencies.isEmpty {
                Text("Add a card that earns points and you can say what they are worth here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(currencies, id: \.name) { currency in
                    ValuationRow(
                        name: currency.name,
                        cents: store.valuation(forCurrencyNamed: currency.name)
                    ) { newValue in
                        store.setValuation(newValue, forCurrencyNamed: currency.name)
                    }
                }
            }
        } header: {
            Text("What your points are worth").textCase(nil)
        } footer: {
            Text("The default of one cent never overpromises. Raise it and point cards climb the ranking; lower it and flat cash back wins more often. Cash back is not listed because a cent is already a cent.")
        }
    }

    // MARK: - Reminders

    private var remindersSection: some View {
        Section {
            HStack {
                Text("Location")
                Spacer(minLength: 8)
                Text(locationStateText)
                    .foregroundStyle(auth.remindersCanWork ? Color.secondary : Color.cardWiseWarning)
            }
            if !auth.remindersCanWork {
                Button("Open Settings") { auth.openSettings() }
            }
            HStack {
                Text("Notifications")
                Spacer(minLength: 8)
                Text(notificationStateText)
                    .foregroundStyle(reminders.isAuthorized ? Color.secondary : Color.cardWiseWarning)
            }
            if reminders.canStillAsk {
                Button("Allow notifications") {
                    Task { await reminders.requestAuthorization() }
                }
            } else if reminders.isBlocked {
                Button("Open Settings") { reminders.openSettings() }
            }
            NavigationLink {
                NotificationSettingsView()
            } label: {
                HStack {
                    Text("How much to say")
                    Spacer(minLength: 8)
                    Text(notifications.policy.intensity.displayName)
                        .foregroundStyle(.secondary)
                }
            }
            #if DEBUG
            NavigationLink("Notification lab") { NotificationLabView() }
            #endif
        } header: {
            Text("Reminders").textCase(nil)
        } footer: {
            Text(remindersFooter)
        }
    }

    /// Both permissions are needed and neither is sufficient, so the footer
    /// names whichever one is actually missing rather than the general idea.
    private var remindersFooter: String {
        if !auth.hasAlways {
            return "Without Always, the app cannot notice you have arrived somewhere while it is closed, which is the only moment a reminder is any use."
        }
        if auth.isApproximate {
            return "Approximate Location is on. iOS does not report arriving somewhere without Precise Location, so reminders cannot fire. Switch on Precise Location in Settings."
        }
        if !reminders.isAuthorized {
            return "The app can see when you arrive somewhere. It just has no way to tell you about it."
        }
        return notifications.policy.intensity.explanation
    }

    private var locationStateText: String {
        if auth.hasAlways { return auth.isApproximate ? "Always, approximate" : "Always" }
        if auth.isBlocked { return "Off" }
        if auth.status == .authorizedWhenInUse { return "Only while open" }
        return "Not set"
    }

    private var notificationStateText: String {
        if reminders.isAuthorized { return "On" }
        if reminders.isBlocked { return "Off" }
        return "Not set"
    }

    // MARK: - Recent activity

    /// The last few things the geofences did, right here rather than a screen
    /// away — the rest of what "Reminder activity" used to show is said
    /// elsewhere, and the list was the part anybody opened it for.
    ///
    /// Three rows, because this is a glance. "See all" only appears when
    /// there is more than a glance's worth.
    private var activitySection: some View {
        Section {
            if monitor.recentEvents.isEmpty {
                Text(RecentActivityView.emptySentence)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(monitor.recentEvents.prefix(3)) { event in
                    ActivityEventRow(event: event)
                }
                if monitor.recentEvents.count > 3 {
                    NavigationLink("See all \(monitor.recentEvents.count)") {
                        RecentActivityView()
                    }
                }
            }
        } header: {
            Text("Recent activity").textCase(nil)
        } footer: {
            Text(watchingFooter)
        }
    }

    private var watchingFooter: String {
        guard monitor.isMonitoring else { return "Not watching any places right now." }
        let count = monitor.monitoredCount
        if count == 0 { return "Watching, but no places nearby pay extra on your cards yet." }
        return count == 1 ? "Watching 1 place right now." : "Watching \(count) places right now."
    }

    // MARK: - Artwork

    private var artworkSection: some View {
        Section {
            Button {
                isShowingArtworkDetail = true
            } label: {
                HStack {
                    Text("Card artwork")
                        .foregroundStyle(.primary)
                    Spacer(minLength: 8)
                    Text(artworkSummary)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            ForEach(CardArtLibrary.attributions(), id: \.self) { line in
                Text(line)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Appearance").textCase(nil)
        }
    }

    private var artworkSummary: String {
        let licensed = CardArtLibrary.assets.count
        if licensed == 0 { return "Drawn" }
        return "\(licensed) licensed"
    }

    // MARK: - Data

    private var dataSection: some View {
        Section {
            HStack {
                Text("Cards on this iPhone")
                Spacer(minLength: 8)
                Text("\(store.cards.count)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Button("Erase everything", role: .destructive) {
                isConfirmingErase = true
            }
        } header: {
            Text("Your data").textCase(nil)
        } footer: {
            Text("No account, no sync, and nothing uploaded anywhere. Everything — your cards, your photos, and the record of what these reminders earned you — lives in this app on this device, and deleting the app takes it with it.")
        }
    }
}

/// A point valuation, in cents, with a stepper rather than a free text field —
/// the plausible range is narrow and typing invites a typo that silently
/// distorts every recommendation.
private struct ValuationRow: View {
    let name: String
    let cents: Double
    var onChange: (Double) -> Void

    var body: some View {
        Stepper(value: Binding(get: { cents }, set: onChange), in: 0.5...3.0, step: 0.1) {
            HStack {
                Text(name)
                Spacer(minLength: 8)
                Text(String(format: "%.1f¢", cents))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}

/// Why the cards look the way they do. Users ask, and the honest answer is
/// more reassuring than a vague one.
private struct CardArtworkExplainerView: View {
    @Environment(\.dismiss) private var dismiss
    #if DEBUG
    @Environment(WalletStore.self) private var store
    #endif

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Apple Wallet shows the real front of your card because your bank sends that image to Apple when you add the card. That artwork belongs to the bank, and we have no such arrangement, so copying it would not be ours to copy.")
                        .font(.subheadline)
                } header: {
                    Text("Why these are not the real card faces").textCase(nil)
                }

                Section {
                    Label("A photo of your own card is an exact match, and never leaves this iPhone.", systemImage: "camera")
                    Label("Otherwise we draw the card: real card proportions, the material you picked, the chip and the contactless mark.", systemImage: "creditcard")
                } header: {
                    Text("What you get instead").textCase(nil)
                }

                #if DEBUG
                artworkAudit
                #endif
            }
            .navigationTitle("Card artwork")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    #if DEBUG
    /// Where the artwork position is visible rather than folklore.
    ///
    /// Debug-only on purpose. A person adding their Amex Gold does not need to
    /// know what a licence manifest is (`docs/card-art.md`, "the complexity
    /// belongs inside the system") — but whoever is *negotiating* one needs to
    /// see, on a real device, which of the three faces each card is actually
    /// getting and what is standing in the way. Building a shipping admin
    /// screen for that would be a rights-management product nobody asked for.
    @ViewBuilder
    private var artworkAudit: some View {
        Section {
            ForEach(store.cards) { card in
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.displayName)
                        .font(.subheadline.weight(.medium))
                    Text(CardArtSource.resolve(for: card).shortLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(card.catalogProductID ?? "no product id — described by hand")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 1)
            }
            if store.cards.isEmpty {
                Text("No cards yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Debug — what each card resolves to").textCase(nil)
        }

        Section {
            if CardArtLibrary.assets.isEmpty {
                Text("Registry is empty, which is the shipping state.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(CardArtLibrary.assets) { asset in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(asset.productID) · v\(asset.assetVersion)")
                            .font(.subheadline.weight(.medium))
                        Text("\(asset.status.displayName) · \(usesLine(asset))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let reason = asset.blockingReason() {
                            Text(reason)
                                .font(.caption)
                                .foregroundStyle(Color.cardWiseWarning)
                        }
                        if let reference = asset.licence.reference {
                            Text(reference)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 1)
                }
            }
        } header: {
            Text("Debug — licence registry").textCase(nil)
        }
    }

    /// "Approved for nothing in particular" has to read as nothing, not as a
    /// blank — that state is the whole reason the field defaults to empty.
    private func usesLine(_ asset: CardArtAsset) -> String {
        let names = asset.permittedUses.map(\.displayName).sorted()
        return names.isEmpty ? "no uses granted" : names.joined(separator: ", ")
    }
    #endif
}

#Preview {
    NavigationStack {
        SettingsView(auth: LocationAuthorization())
    }
    .environment(WalletStore.previewStore())
    .environment(ReminderCenter())
    .environment(RegionMonitor())
    .environment(ImpactStore.previewStore())
    .environment(NearbyPlacesStore())
}
