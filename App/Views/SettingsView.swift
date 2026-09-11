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
    let auth: LocationAuthorization

    @State private var isConfirmingErase = false
    @State private var isShowingArtworkDetail = false

    var body: some View {
        List {
            valuationSection
            remindersSection
            artworkSection
            dataSection
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isShowingArtworkDetail) {
            CardArtworkExplainerView()
        }
        .alert("Erase everything?", isPresented: $isConfirmingErase) {
            Button("Cancel", role: .cancel) {}
            Button("Erase", role: .destructive) { store.eraseEverything() }
        } message: {
            Text("Removes every card and every photo from this iPhone. There is no account and no backup, so this cannot be undone.")
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
                    .foregroundStyle(auth.hasAlways ? Color.secondary : Color.cardWiseWarning)
            }
            if !auth.hasAlways {
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
                RegionActivityView()
            } label: {
                HStack {
                    Text("Reminder activity")
                    Spacer(minLength: 8)
                    Text(watchingSummary)
                        .foregroundStyle(.secondary)
                }
            }
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
        if !reminders.isAuthorized {
            return "The app can see when you arrive somewhere. It just has no way to tell you about it."
        }
        return "Limits on how often you are nudged arrive with the reminders themselves."
    }

    private var watchingSummary: String {
        guard monitor.isMonitoring else { return "Off" }
        let count = monitor.monitoredCount
        return count == 0 ? "No places yet" : "\(count) places"
    }

    private var locationStateText: String {
        if auth.hasAlways { return "Always" }
        if auth.isBlocked { return "Off" }
        if auth.status == .authorizedWhenInUse { return "Only while open" }
        return "Not set"
    }

    private var notificationStateText: String {
        if reminders.isAuthorized { return "On" }
        if reminders.isBlocked { return "Off" }
        return "Not set"
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
            ForEach(CardArtLibrary.attributions, id: \.self) { line in
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
            Text("No account, no sync, no analytics. Everything lives in this app on this device, and deleting the app takes it with it.")
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
}

#Preview {
    NavigationStack {
        SettingsView(auth: LocationAuthorization())
    }
    .environment(WalletStore.previewStore())
    .environment(ReminderCenter())
    .environment(RegionMonitor())
}
