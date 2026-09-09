import SwiftUI
import CoreLocation

/// The screen shown *before* the iOS location prompt.
///
/// The spec calls the permission ask the biggest drop-off in the funnel, and it
/// is right: "Always Allow" is the scariest switch in iOS and the system prompt
/// gives us two lines to justify it. So the case gets made here, in our own
/// words, where a No costs nothing — iOS only lets an app ask once, and a No
/// there is permanent.
///
/// The view has three states, driven entirely by the authorization status:
/// the ask, the Settings fallback once iOS will not prompt again, and the
/// confirmation.
struct LocationPrimerView: View {

    let auth: LocationAuthorization
    var onFinish: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    if auth.hasAlways {
                        grantedBody
                    } else if auth.isBlocked {
                        blockedBody
                    } else {
                        askBody
                    }
                }
                .padding(26)
            }
            footer
        }
        .presentationDetents([.large])
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
        if auth.hasAlways { return "checkmark.circle.fill" }
        if auth.isBlocked { return "gearshape" }
        return "location.circle.fill"
    }

    private var headerTitle: String {
        if auth.hasAlways { return "You are all set" }
        if auth.isBlocked { return "Turn it on in Settings" }
        return "Get told before you pay"
    }

    private var headerSubtitle: String {
        if auth.hasAlways {
            return "We will nudge you a few minutes after you walk in somewhere, with the card that earns the most."
        }
        if auth.isBlocked {
            return "iOS only asks once, and it has already asked. The switch lives in Settings now."
        }
        return "For the reminder to beat you to the till, iOS needs to let us notice where you are while the app is closed."
    }

    // MARK: - Bodies

    private var askBody: some View {
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

    private var blockedBody: some View {
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

    private var grantedBody: some View {
        VStack(alignment: .leading, spacing: 18) {
            point(
                icon: "mappin.and.ellipse",
                title: "Nothing else to do",
                detail: "Add the rest of your cards and we will take it from here."
            )
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 10) {
            Button {
                if auth.hasAlways {
                    finish()
                } else {
                    auth.requestAlwaysAccess()
                }
            } label: {
                Text(primaryTitle)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            if !auth.hasAlways {
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
        if auth.hasAlways { return "Done" }
        if auth.isBlocked { return "Open Settings" }
        return "Turn on reminders"
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
}
