import MapKit
import Observation
import SwiftUI
import CardKit

/// Address suggestions while somebody types — "155 Mitc" offers
/// "155 Mitchell St" before they have finished the word.
///
/// **Apple's completer, not Google's, and that is the whole design.** The
/// place search on the map is Google's and billed per request, which is why it
/// only runs when you press Return: "Sta" is not a question anybody meant to
/// ask. Suggesting on every keystroke from that source would be a bill for
/// "1", "15", "155", "155 M" and so on. `MKLocalSearchCompleter` is on the
/// phone already, needs no key, costs nothing per keystroke, and an address is
/// exactly the thing it is good at.
///
/// Addresses only. A café suggested by Apple would be a second, disagreeing
/// answer to the question the Google search on Return already answers.
@Observable
final class AddressCompleter: NSObject, MKLocalSearchCompleterDelegate {

    private(set) var suggestions: [MKLocalSearchCompletion] = []

    @ObservationIgnored private let completer = MKLocalSearchCompleter()
    /// Whether a late answer is still wanted. `cancel()` stops the query, but
    /// an answer already on its way can still land after the field has been
    /// cleared or submitted — and a dropdown reappearing under a search that
    /// has already run reads as the app ignoring you.
    @ObservationIgnored private var isListening = false

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
    }

    /// Feeds whatever is in the box.
    ///
    /// Fewer than three characters asks nothing: "1" matches every street in
    /// the country. The region only biases the answers towards where the
    /// person is — it does not exclude an address in another city.
    func update(_ text: String, near coordinate: GeoCoordinate?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else {
            clear()
            return
        }
        if let coordinate, coordinate.isValid {
            completer.region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude),
                latitudinalMeters: 80_000,
                longitudinalMeters: 80_000
            )
        }
        isListening = true
        completer.queryFragment = trimmed
    }

    func clear() {
        isListening = false
        completer.cancel()
        suggestions = []
    }

    /// Turns a picked suggestion into somewhere on the map. Nil when Apple
    /// cannot place it, which the caller says out loud.
    func coordinate(for suggestion: MKLocalSearchCompletion) async -> GeoCoordinate? {
        let request = MKLocalSearch.Request(completion: suggestion)
        request.resultTypes = .address
        guard let response = try? await MKLocalSearch(request: request).start(),
              let item = response.mapItems.first else { return nil }
        let point = item.placemark.coordinate
        let coordinate = GeoCoordinate(latitude: point.latitude, longitude: point.longitude)
        return coordinate.isValid ? coordinate : nil
    }

    // MARK: - MKLocalSearchCompleterDelegate

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        guard isListening else { return }
        // Four, not the dozen Apple offers. The list sits over the map, and
        // past four the right answer is to keep typing.
        suggestions = Array(completer.results.prefix(4))
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        // No network, or no match. Either way the honest dropdown is none.
        suggestions = []
    }
}

/// The dropdown under a location field.
///
/// **A solid grouped-secondary fill, not a material.** It floats over the map,
/// which is exactly where a material is tempting — and a hierarchical style on
/// a material paints nothing, which is how the map sheet's secondary text once
/// went invisible. Explicit `Color`s throughout for the same reason.
struct AddressSuggestionList: View {
    let suggestions: [MKLocalSearchCompletion]
    var onPick: (MKLocalSearchCompletion) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(suggestions.enumerated()), id: \.offset) { index, suggestion in
                if index > 0 {
                    Hairline(inset: 48)
                }
                Button {
                    onPick(suggestion)
                } label: {
                    HStack(spacing: Metric.snug) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Color.cardAheadBlue)
                            .frame(width: 24)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(suggestion.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.primary)
                            if !suggestion.subtitle.isEmpty {
                                Text(suggestion.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(Color.secondary)
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: Metric.minimumTarget)
                    .padding(.horizontal, Metric.snug)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows the map around this address")
            }
        }
        .padding(.vertical, 4)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: Metric.tileRadius, style: .continuous)
        )
        .shadow(color: Color.cardAheadNavy.opacity(0.12), radius: 12, y: 4)
    }
}
