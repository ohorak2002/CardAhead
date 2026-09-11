import SwiftUI
import CardKit

/// What the geofences have actually been doing.
///
/// Everything interesting about this feature happens while the app is closed
/// and the phone is in a pocket. Without a list like this, "it did not remind
/// me" and "it never noticed I was there" and "there was nothing to remind me
/// about" are indistinguishable — to the user and to anyone trying to fix it.
struct RegionActivityView: View {

    @Environment(RegionMonitor.self) private var monitor

    var body: some View {
        List {
            statusSection
            if monitor.recentEvents.isEmpty {
                Section {
                    Text("Nothing yet. Events show up here as you arrive at and leave the places being watched.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(monitor.recentEvents) { event in
                        EventRow(event: event)
                    }
                } header: {
                    Text("Recent").textCase(nil)
                } footer: {
                    Text("The last \(monitor.recentEvents.count) of at most 40. Older ones are dropped.")
                }

                Section {
                    Button("Clear this list", role: .destructive) { monitor.clearEvents() }
                }
            }
        }
        .navigationTitle("Reminder activity")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var statusSection: some View {
        Section {
            LabeledContent("Watching") {
                Text(monitor.isMonitoring ? "\(monitor.monitoredCount) places" : "Off")
                    .foregroundStyle(monitor.isMonitoring ? Color.secondary : Color.orange)
            }
            LabeledContent("Places come from") {
                Text(monitor.sourceDescription)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
            }
            if let waiting = monitor.tracker.pending.first {
                LabeledContent("Waiting on") {
                    Text(waiting.merchant.name)
                        .foregroundStyle(.secondary)
                }
            }
        } footer: {
            Text(monitor.monitoredCount == 0
                 ? "iOS lets an app watch twenty places at once, and we spend them on the nearest shops where one of your cards pays extra."
                 : "iOS lets an app watch twenty places at once. These are the nearest ones where one of your cards pays extra, and they change as you move.")
        }
    }
}

private struct EventRow: View {
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
        case .confirmed: return .green
        case .failed: return .orange
        case .cancelled, .skipped: return .secondary
        default: return .accentColor
        }
    }
}

#Preview {
    NavigationStack {
        RegionActivityView()
            .environment(RegionMonitor())
    }
}
