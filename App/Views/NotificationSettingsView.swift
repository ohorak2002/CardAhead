import SwiftUI
import CardKit

/// How much CardWise is allowed to say, and about what.
///
/// **The whole screen is refinement, not setup.** Every control here already
/// has an answer that works — Balanced, quiet from ten to eight, every
/// category on — and somebody who never opens this screen gets an app that
/// behaves sensibly. That is the difference between a setting and a
/// configuration step, and an app that needs the second one before it is any
/// good has handed the user its homework.
///
/// So: no onboarding step points here, nothing is marked "recommended", and
/// the categories list starts fully enabled rather than as a set of empty
/// checkboxes waiting to be filled in.
struct NotificationSettingsView: View {

    @Environment(NotificationPolicyStore.self) private var notifications
    @Environment(WalletStore.self) private var store

    var body: some View {
        List {
            intensitySection
            quietHoursSection
            categoriesSection
            mutedSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - How much

    private var intensitySection: some View {
        Section {
            ForEach(NotificationIntensity.allCases, id: \.self) { intensity in
                Button {
                    notifications.setIntensity(intensity)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: Metric.gap) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(intensity.displayName)
                                .foregroundStyle(Color.primary)
                            Text(intensity.explanation)
                                .font(.footnote)
                                .foregroundStyle(Color.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        if notifications.policy.intensity == intensity {
                            Image(systemName: "checkmark")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Color.cardWiseBlue)
                        }
                    }
                }
                .accessibilityAddTraits(
                    notifications.policy.intensity == intensity ? [.isSelected] : []
                )
            }
        } header: {
            Text("How often").textCase(nil)
        } footer: {
            Text("These change how good an opportunity has to be, and how many you hear about in a day. They do not change what CardWise watches for.")
        }
    }

    // MARK: - When not to

    private var quietHoursSection: some View {
        Section {
            Toggle("Quiet hours", isOn: quietHoursEnabled)
            if notifications.policy.quietHours.isEnabled {
                QuietHourPicker(
                    title: "From",
                    minutes: quietStart
                )
                QuietHourPicker(
                    title: "Until",
                    minutes: quietEnd
                )
            }
        } header: {
            Text("Quiet hours").textCase(nil)
        } footer: {
            Text("Nothing is sent during these hours. It is not held back and delivered later — a reminder is only any use at the till it is about.")
        }
    }

    private var quietHoursEnabled: Binding<Bool> {
        Binding(
            get: { notifications.policy.quietHours.isEnabled },
            set: { isOn in
                var hours = notifications.policy.quietHours
                hours.isEnabled = isOn
                notifications.setQuietHours(hours)
            }
        )
    }

    private var quietStart: Binding<Int> {
        Binding(
            get: { notifications.policy.quietHours.startMinutes },
            set: { minutes in
                var hours = notifications.policy.quietHours
                hours.startMinutes = minutes
                notifications.setQuietHours(hours)
            }
        )
    }

    private var quietEnd: Binding<Int> {
        Binding(
            get: { notifications.policy.quietHours.endMinutes },
            set: { minutes in
                var hours = notifications.policy.quietHours
                hours.endMinutes = minutes
                notifications.setQuietHours(hours)
            }
        )
    }

    // MARK: - About what

    /// Only the categories this wallet actually earns on.
    ///
    /// **A list of seventeen switches, fifteen of which do nothing, is not a
    /// setting — it is a quiz.** A geofence is only ever registered for a
    /// category some card pays a bonus on, so switching off a category the
    /// wallet has no rate for changes nothing at all, and offering it implies
    /// otherwise. The list grows as cards are added, which is the right
    /// moment for it to appear.
    private var relevantCategories: [SpendingCategory] {
        let earning = Set(store.cards.flatMap { $0.bonusCategories() })
        return SpendingCategory.allCases
            .filter { earning.contains($0) }
            .sorted { $0.displayName < $1.displayName }
    }

    @ViewBuilder
    private var categoriesSection: some View {
        Section {
            if relevantCategories.isEmpty {
                Text("Once a card in your wallet earns extra somewhere, that kind of place appears here.")
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
            } else {
                ForEach(relevantCategories, id: \.self) { category in
                    Toggle(isOn: enabled(category)) {
                        Label {
                            Text(category.placePhrase)
                        } icon: {
                            Image(systemName: category.symbolName)
                                .foregroundStyle(category.tint)
                        }
                    }
                }
            }
        } header: {
            Text("Kinds of place").textCase(nil)
        } footer: {
            Text("Switched off, CardWise keeps watching and keeps counting — it just says nothing when you arrive.")
        }
    }

    private func enabled(_ category: SpendingCategory) -> Binding<Bool> {
        Binding(
            get: { notifications.policy.allows(category: category) },
            set: { notifications.setCategory(category, enabled: $0) }
        )
    }

    // MARK: - Muted shops

    /// Shown only when there is something in it.
    ///
    /// The list holds place ids, not names — see `NotificationPolicy` on why
    /// as little as possible is kept — so a row can only say that *a* place is
    /// muted and when it stops being. That is thin, and it is still worth
    /// having: without it a mute is a thing somebody did once on a lock screen
    /// and can never undo.
    @ViewBuilder
    private var mutedSection: some View {
        if !notifications.policy.mutedMerchants.isEmpty {
            Section {
                ForEach(mutedIDs, id: \.self) { id in
                    HStack {
                        Text(mutedLabel(for: id))
                        Spacer(minLength: 8)
                        Button("Unmute") { notifications.unmute(merchantID: id) }
                            .buttonStyle(.borderless)
                    }
                }
            } header: {
                Text("Muted places").textCase(nil)
            }
        }
    }

    private var mutedIDs: [String] {
        notifications.policy.mutedMerchants.keys.sorted()
    }

    private func mutedLabel(for id: String) -> String {
        guard let until = notifications.policy.mutedMerchants[id] else { return "A place" }
        if until == .distantFuture { return "A place, muted for good" }
        return "A place, until \(until.formatted(date: .abbreviated, time: .shortened))"
    }
}

/// One end of the quiet window, on the hour or the half hour.
///
/// A `Picker` of 48 rows rather than a `DatePicker`: this is a time of day and
/// not a moment, and a wheel that offers 3:47am is offering a precision nobody
/// wants for "stop bothering me at night".
private struct QuietHourPicker: View {

    let title: String
    @Binding var minutes: Int

    private static let choices: [Int] = stride(from: 0, to: 24 * 60, by: 30).map { $0 }

    var body: some View {
        Picker(title, selection: $minutes) {
            ForEach(Self.choices, id: \.self) { value in
                Text(Self.label(value)).tag(value)
            }
        }
    }

    private static func label(_ minutes: Int) -> String {
        var components = DateComponents()
        components.hour = minutes / 60
        components.minute = minutes % 60
        let calendar = Calendar.current
        guard let date = calendar.date(from: components) else { return "\(minutes / 60):00" }
        return date.formatted(date: .omitted, time: .shortened)
    }
}
