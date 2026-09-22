import SwiftUI
import CoreLocation

/// The screen shown *before* each of the two iOS prompts this app depends on.
///
/// The spec calls the permission ask the biggest drop-off in the funnel, and it
/// is right: "Always Allow" is the scariest switch in iOS and the system prompt
/// gives us two lines to justify it. So the case gets made here, in our own
/// words, where a No costs nothing — iOS only lets an app ask once, and a No
/// there is permanent.
///
/// It runs as two steps, in this order and not the other one. Notifications are
/// asked for **after** location, because until the app can tell where you are
/// there is nothing it could ever notify you about, and a permission prompt
/// with no answer to "why?" is a prompt that gets declined. Neither is asked for
/// on a cold launch.
struct LocationPrimerView: View {

    let auth: LocationAuthorization
    var onFinish: () -> Void

    @Environment(ReminderCenter.self) private var reminders
    @Environment(\.dismiss) private var dismiss

    private enum Step {
        case location
        case notifications
        case done
    }

    private var step: Step {
        if !auth.hasAlways { return .location }
        if !reminders.isAuthorized { return .notifications }
        return .done
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    switch step {
                    case .location:
                        if auth.isBlocked { locationBlockedBody } else { locationAskBody }
                    case .notifications:
                        if reminders.isBlocked { notificationsBlockedBody } else { notificationsAskBody }
                    case .done:
                        grantedBody
                    }
                }
                .padding(26)
            }
            footer
        }
        .presentationDetents([.large])
        .task { await reminders.refreshStatus() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: headerIcon)
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(.tint)

            Text(headerTitle)
                .font(.title2.weight(.bold))

            Text(headerSubtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var headerIcon: String {
        switch step {
        case .location: return auth.isBlocked ? "gearshape" : "location.circle.fill"
        case .notifications: return reminders.isBlocked ? "gearshape" : "bell.badge"
        case .done: return "checkmark.circle.fill"
        }
    }

    private var headerTitle: String {
        switch step {
        case .location: return auth.isBlocked ? "Turn it on in Settings" : "Get told before you pay"
        case .notifications: return reminders.isBlocked ? "Let the reminder appear" : "One more switch"
        case .done: return "You are all set"
        }
    }

    private var headerSubtitle: String {
        switch step {
        case .location:
            return auth.isBlocked
                ? "iOS only asks once, and it has already asked. The switch lives in Settings now."
                : "For the reminder to beat you to the till, iOS needs to let us notice where you are while the app is closed."
        case .notifications:
            return reminders.isBlocked
                ? "Notifications are switched off for this app, so there is nowhere for the reminder to go."
                : "Knowing where you are is only half of it. The reminder itself is a notification, and those need their own yes."
        case .done:
            return "We will nudge you a few minutes after you walk in somewhere, with the card that earns the most."
        }
    }

    // MARK: - Bodies

    private var locationAskBody: some View {
        VStack(alignment: .leading, spacing: 18) {
            point(
                icon: "bell.badge",
                title: "It has to work with the app shut",
                detail: "Nobody opens a rewards app before paying. A reminder that only works while you are looking at it is no reminder at all."
            )
            point(
                icon: "iphone",
                title: "Your location stays on your iPhone",
                detail: "We look up the shop by coordinates alone. Nothing that identifies you is attached to it, and no location leaves the device."
            )
            point(
                icon: "battery.100",
                title: "It does not sit there draining the battery",
                detail: "iOS watches the geofences for us and wakes the app only when you cross one. No constant GPS."
            )

            calloutBox(
                "iOS will call this Always Allow.",
                detail: "You may see two prompts: allow it while using the app first, then change it to Always. Both are needed."
            )
        }
    }

    private var locationBlockedBody: some View {
        VStack(alignment: .leading, spacing: 18) {
            numberedStep(1, "Open Settings below")
            numberedStep(2, "Tap Location")
            numberedStep(3, "Choose Always")

            calloutBox(
                "Apple does not let apps jump to a single switch.",
                detail: "The button below opens this app's page in Settings, which is as close as iOS allows. Location is the row you want."
            )
        }
    }

    private var notificationsAskBody: some View {
        VStack(alignment: .leading, spacing: 18) {
            point(
                icon: "text.bubble",
                title: "It only speaks when it has something to say",
                detail: "A few minutes after you walk into somewhere one of your cards pays more than the rest. If every card would earn the same there, you hear nothing."
            )
            point(
                icon: "creditcard",
                title: "One notification, one card",
                detail: "It names the card and why. Tap it and that card is already open, so you can check the small print before you pay."
            )
            point(
                icon: "hand.raised",
                title: "Nothing else will ever use this",
                detail: "No marketing or daily notification summary. Impact sharing is optional and controlled separately."
            )
        }
    }

    private var notificationsBlockedBody: some View {
        VStack(alignment: .leading, spacing: 18) {
            numberedStep(1, "Open Settings below")
            numberedStep(2, "Tap Notifications")
            numberedStep(3, "Switch on Allow Notifications")

            calloutBox(
                "Everything else is already in place.",
                detail: "The app can see when you arrive somewhere. It just has no way to tell you about it."
            )
        }
    }

    private var grantedBody: some View {
        VStack(alignment: .leading, spacing: 18) {
            point(
                icon: "mappin.and.ellipse",
                title: "Nothing else to do",
                detail: "Add the rest of your cards and we will take it from here."
            )
            point(
                icon: "list.bullet.rectangle",
                title: "You can check its work",
                detail: "Settings has a list of everywhere it noticed you arriving, and what it did about each one."
            )
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 10) {
            Button {
                advance()
            } label: {
                Text(primaryTitle)
            }
            .buttonStyle(.cardWisePrimary)

            if step != .done {
                Button("Not now") { finish() }
                    .font(.subheadline)
            }
        }
        .padding(.horizontal, 26)
        .padding(.top, 12)
        .padding(.bottom, 20)
        .background(.bar)
    }

    private var primaryTitle: String {
        switch step {
        case .location: return auth.isBlocked ? "Open Settings" : "Turn on reminders"
        case .notifications: return reminders.isBlocked ? "Open Settings" : "Allow notifications"
        case .done: return "Done"
        }
    }

    private func advance() {
        switch step {
        case .location:
            auth.requestAlwaysAccess()
        case .notifications:
            if reminders.isBlocked {
                reminders.openSettings()
            } else {
                Task { await reminders.requestAuthorization() }
            }
        case .done:
            finish()
        }
    }

    private func finish() {
        onFinish()
        dismiss()
    }

    // MARK: - Pieces

    private func point(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.tint)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func numberedStep(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text("\(number)")
                .font(.footnote.weight(.bold).monospacedDigit())
                .foregroundStyle(.tint)
                .frame(width: 24)
            Text(text).font(.subheadline)
        }
    }

    private func calloutBox(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.footnote.weight(.semibold))
            Text(detail).font(.footnote).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

#Preview {
    LocationPrimerView(auth: LocationAuthorization()) {}
        .environment(ReminderCenter())
}
