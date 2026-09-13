import CoreLocation
import SwiftUI
import CardKit

/// The map's standing preferences, as opposed to the filter sheet's
/// this-minute ones.
///
/// The two edit the same `MapFilter`, and that is on purpose rather than an
/// oversight: there is one answer to "how far out does the map look" and one
/// to "which kinds of place does it show", and a settings screen that kept its
/// own second copy would be a second answer free to disagree with what is on
/// the map. What differs is the register — the sheet is a quick narrowing you
/// undo in a minute, this is where you come to say "I never want to see
/// hotels" once.
///
/// It applies immediately, unlike the sheet. A settings screen with an Apply
/// button is a settings screen nobody trusts.
struct MapSettingsView: View {

    @Environment(NearbyPlacesStore.self) private var places
    let auth: LocationAuthorization

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: Metric.tight) {
                    HStack {
                        Text("How far out")
                        Spacer(minLength: Metric.tight)
                        Text(places.filter.distance.displayName)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    // A slider over five named steps rather than a continuous
                    // one: the five are the only radii the provider is ever
                    // asked for, and a slider that can land on 2.7 miles
                    // implies a precision this does not have.
                    Slider(
                        value: Binding(
                            get: { Double(index(of: places.filter.distance)) },
                            set: { places.filter.distance = MapDistance.allCases[Int($0.rounded())] }
                        ),
                        in: 0...Double(MapDistance.allCases.count - 1),
                        step: 1
                    )
                    .tint(Color.cardWiseBlue)
                    HStack {
                        ForEach(MapDistance.allCases, id: \.self) { distance in
                            Text(distance.shortName)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Distance range").textCase(nil)
            } footer: {
                Text("The place lookup returns at most twenty results, however far out you ask. A wide radius spreads those twenty thinner rather than finding more.")
            }

            Section {
                ForEach(MapCategory.allCases, id: \.self) { category in
                    Toggle(isOn: Binding(
                        get: { places.filter.includes(category) },
                        set: { _ in places.filter.toggle(category) }
                    )) {
                        Label {
                            Text(category.displayName)
                        } icon: {
                            Image(systemName: category.symbolName)
                                .foregroundStyle(tint(for: category))
                        }
                    }
                    .tint(Color.cardWiseBlue)
                }
            } header: {
                Text("Kinds of place").textCase(nil)
            } footer: {
                Text("Turning the last one off shows everything again, because a map with nothing on it is not a setting anybody wanted.")
            }

            Section {
                HStack {
                    Text("Location")
                    Spacer(minLength: Metric.tight)
                    Text(locationStateText)
                        .foregroundStyle(auth.isBlocked ? Color.cardWiseWarning : Color.secondary)
                }
                if auth.isBlocked {
                    Button("Open Settings") { auth.openSettings() }
                }
                HStack {
                    Text("Places come from")
                    Spacer(minLength: Metric.tight)
                    Text(places.sourceDescription)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            } header: {
                Text("Location services").textCase(nil)
            } footer: {
                Text("The map works on While Using access — the same permission the reminders ask for on their way to Always. Where you are is sent to the place provider to ask what is nearby, and is never stored anywhere off this iPhone.")
            }
        }
        .navigationTitle("Map settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func index(of distance: MapDistance) -> Int {
        MapDistance.allCases.firstIndex(of: distance) ?? 0
    }

    private func tint(for category: MapCategory) -> Color {
        category.benefitGroup?.tint ?? Color(red: 0.392, green: 0.455, blue: 0.545)
    }

    /// The map only needs While Using, so "Always" and "While Using" are both
    /// simply on here — unlike the reminders section, where the difference
    /// between them is the whole product.
    private var locationStateText: String {
        if auth.hasAlways { return "Always" }
        if auth.status == .authorizedWhenInUse { return "While using CardWise" }
        if auth.isBlocked { return "Off" }
        return "Not asked yet"
    }
}

#Preview {
    NavigationStack {
        MapSettingsView(auth: LocationAuthorization())
    }
    .environment(NearbyPlacesStore())
}
