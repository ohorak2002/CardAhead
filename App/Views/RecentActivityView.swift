import SwiftUI
import CardKit

/// Everything the geofences have done lately — arrivals, departures,
/// reminders sent and skipped — and nothing else.
///
/// Everything interesting about this feature happens while the app is closed
/// and the phone is in a pocket. Without a list like this, "it did not remind
/// me" and "it never noticed I was there" and "there was nothing to remind me
/// about" are indistinguishable — to the user and to anyone trying to fix it.
///
/// **This used to be "Reminder activity", and it was a status screen with the
/// list at the bottom.** How many places are watched, where they come from,
/// what is pending — true, and already said elsewhere: the watching count is
/// the footer of the Settings section that links here, the place source is on
/// the map's own settings, and a missing notification permission is flagged
/// in Reminders. What only this screen can show is the list, so the list is
/// the screen.
struct RecentActivityView: View {

    @Environment(RegionMonitor.self) private var monitor

    var body: some View {
        List {
            if monitor.recentEvents.isEmpty {
                Section {
                    Text(RecentActivityView.emptySentence)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(monitor.recentEvents) { event in
                        ActivityEventRow(event: event)
                    }
                } footer: {
                    Text("The last \(monitor.recentEvents.count) of at most 40. Older ones are dropped.")
                }

                Section {
                    Button("Clear this list", role: .destructive) { monitor.clearEvents() }
                }
            }
        }
        .navigationTitle("Recent activity")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Shared with the Settings section, so an empty list reads the same
    /// wherever it is empty.
    static let emptySentence = "Nothing yet. Arrivals and departures at the places being watched show up here."
}

/// One thing a geofence did, and when.
struct ActivityEventRow: View {
    let event: RegionEvent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: event.symbolName)
                .font(.footnote)
                .foregroundStyle(tint)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(event.detail)
                    .font(.subheadline)
                Text(event.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var tint: Color {
        switch event.kind {
        case .confirmed: return .cardWiseSuccess
        case .failed: return .cardWiseWarning
        case .cancelled, .skipped: return .secondary
        default: return .accentColor
        }
    }
}

#Preview {
    NavigationStack {
        RecentActivityView()
            .environment(RegionMonitor())
    }
}
