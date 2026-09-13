import MapKit
import SwiftUI
import CardKit

/// The Map tab: what is around you, and which card wins at each of it.
///
/// **Why this is a tab and not a sheet hanging off Home.** Everything else in
/// CardWise answers "which card, here, now" — the reminder, the wallet, the
/// benefits shelf. This answers a question nobody could ask before: *where*,
/// within a few miles, is a card in this wallet worth more than the one you
/// would have reached for anyway. That is a browsing job with its own
/// vocabulary — a radius, a kind of shop, a search box — and hanging it off
/// another screen would have made it the tail on the wallet all over again.
///
/// **MapKit, not a Google Maps SDK.** The places come from Google because
/// `MerchantCategoryMap` has been written against Google's type vocabulary
/// since before any of this existed, and a second mapping is the kind of
/// duplication that rots. But *drawing* a map is not where that matters:
/// MapKit is on the phone already, needs no second key, no package
/// dependency and no attribution overlay, and looks like the rest of iOS. The
/// data and the canvas do not have to come from the same company.
///
/// Three things this screen will not do:
///
/// - **It does not invent a pin.** With no Places key it shows the user's own
///   location and says in plain words that it has nowhere to get shops from.
/// - **It does not claim a reward it cannot derive.** A place whose type maps
///   onto no earning category says so; it does not guess "shopping" from a
///   name.
/// - **It does not re-query on every pan.** Each lookup is billed. Panning
///   offers a "Search this area" button and waits to be asked.
struct NearbyMapView: View {

    @Environment(NearbyPlacesStore.self) private var places

    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var selectedID: String?
    @State private var openPlace: MapPlace?
    @State private var isFiltering = false
    /// Where the camera is now, as opposed to where the results were measured
    /// from. The gap between the two is what raises "Search this area".
    @State private var cameraCenter: GeoCoordinate?

    var body: some View {
        @Bindable var places = places

        VStack(spacing: 0) {
            header
            controls
            map
            resultsList
        }
        .background(Color(.systemGroupedBackground))
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $isFiltering) {
            MapFiltersView(filter: $places.filter)
        }
        .navigationDestination(item: $openPlace) { place in
            PlaceDetailView(place: place)
        }
        .onAppear {
            places.start()
            // A seeded run, and any return to this tab, already has a centre.
            // `onChange` only fires on a *change*, so the first look at an
            // anchor that was set before this view existed needs this.
            focusCamera()
        }
        .onChange(of: places.center) { _, _ in focusCamera() }
        .onChange(of: places.filter.distance) { _, _ in focusCamera() }
        // The first look almost always happens before the lookup answers, so
        // the fit has to happen again when the places land. Not if the map has
        // been taken somewhere, though: refitting under somebody's thumb is
        // the map yanking itself out of their hand.
        .onChange(of: places.places.count) { _, _ in
            guard pannedAway == nil else { return }
            focusCamera()
        }
    }

    // MARK: - The navy top

    private var header: some View {
        ScreenHeader(title: "Nearby Map") {
            HeaderButton(symbolName: "slider.horizontal.3", label: "Filters") {
                isFiltering = true
            }
        }
    }

    // MARK: - Search and chips

    private var controls: some View {
        @Bindable var places = places

        return VStack(spacing: Metric.snug) {
            HStack(spacing: Metric.tight) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search places, stores, or categories", text: $places.searchText)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .onSubmit { places.runSearch() }
                if !places.searchText.isEmpty {
                    Button {
                        places.clearSearch()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, Metric.snug)
            .padding(.vertical, 10)
            // **Not `.background.secondary`.** In dark mode that is a visible
            // grey, but on the light grouped background it resolves to very
            // nearly the same grey as the page and the field disappeared
            // entirely — which is what the first screenshots showed. The
            // grouped-secondary role is white on light and grey on dark, which
            // is the one that means "a control sitting on a grouped page".
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: Metric.tileRadius, style: .continuous))
            .padding(.horizontal, Metric.margin)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Metric.tight) {
                    FilterChip(
                        title: "All",
                        isOn: places.filter.isShowingEverything,
                        tint: .cardWiseBlue
                    ) {
                        places.filter.showEverything()
                    }
                    ForEach(MapCategory.quickFilters, id: \.self) { category in
                        FilterChip(
                            title: category.shortName,
                            isOn: !places.filter.isShowingEverything && places.filter.categories == [category],
                            tint: tint(for: category)
                        ) {
                            // A chip is a "show me only this" switch, and
                            // tapping the one already on goes back to
                            // everything. Ticking several at once is what the
                            // filter sheet is for.
                            if places.filter.categories == [category] {
                                places.filter.showEverything()
                            } else {
                                places.filter.showOnly(category)
                            }
                        }
                    }
                    Menu {
                        Picker("Distance", selection: $places.filter.distance) {
                            ForEach(MapDistance.allCases, id: \.self) { distance in
                                Text(distance.displayName).tag(distance)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(places.filter.distance.shortName)
                            Image(systemName: "chevron.down")
                                .font(.caption2.weight(.semibold))
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.primary)
                        .padding(.horizontal, Metric.snug)
                        .padding(.vertical, 7)
                        .background(Color(.secondarySystemGroupedBackground), in: Capsule())
                    }
                }
                .padding(.horizontal, Metric.margin)
            }
        }
        .padding(.vertical, Metric.snug)
    }

    // MARK: - The map

    /// 300 points: enough map to be worth panning, and short enough that the
    /// first three rows of the list are on screen under it. Deliberately a
    /// constant rather than a fraction measured with a `GeometryReader` —
    /// measuring a container to size something inside it is the circular trap
    /// that cost a whole CI round trip on the wallet stack.
    private static let mapHeight: CGFloat = 300

    private var map: some View {
        ZStack(alignment: .bottom) {
            Map(position: $camera, selection: $selectedID) {
                UserAnnotation()
                ForEach(places.results) { result in
                    Annotation(
                        result.place.name,
                        coordinate: CLLocationCoordinate2D(
                            latitude: result.place.coordinate.latitude,
                            longitude: result.place.coordinate.longitude
                        ),
                        anchor: .bottom
                    ) {
                        MapPin(
                            category: result.place.mapCategory,
                            isOpportunity: result.isOpportunity,
                            isSelected: selectedID == result.id
                        )
                    }
                    .tag(result.id)
                    .annotationTitles(.hidden)
                }
            }
            .mapControls {
                MapCompass()
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                cameraCenter = GeoCoordinate(
                    latitude: context.region.center.latitude,
                    longitude: context.region.center.longitude
                )
            }

            VStack(spacing: Metric.tight) {
                if let panned = pannedAway {
                    Button {
                        places.searchArea(around: panned)
                        cameraCenter = nil
                    } label: {
                        Label("Search this area", systemImage: "arrow.clockwise")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, Metric.regular)
                            .padding(.vertical, Metric.tight)
                            .background(.background, in: Capsule())
                            .shadow(color: Color.cardWiseNavy.opacity(0.18), radius: 8, y: 2)
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
                if let selected {
                    SelectedPlaceCard(result: selected) {
                        openPlace = selected.place
                    } onDismiss: {
                        selectedID = nil
                    }
                    .padding(.horizontal, Metric.snug)
                    .padding(.bottom, Metric.snug)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.top, Metric.snug)

            recenterButton
        }
        .frame(height: Self.mapHeight)
        .clipShape(RoundedRectangle(cornerRadius: Metric.cardRadius, style: .continuous))
        .padding(.horizontal, Metric.margin)
        .animation(.snappy(duration: 0.25), value: selectedID)
    }

    private var recenterButton: some View {
        VStack {
            Spacer(minLength: 0)
            HStack {
                Spacer(minLength: 0)
                Button {
                    places.recenterOnUser()
                } label: {
                    Image(systemName: "location.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.cardWiseBlue)
                        .frame(width: 38, height: 38)
                        .background(.background, in: Circle())
                        .shadow(color: Color.cardWiseNavy.opacity(0.18), radius: 6, y: 2)
                }
                .accessibilityLabel("Back to my location")
            }
        }
        .padding(Metric.snug)
        // Out of the way of the selected-place card, which owns the bottom of
        // the map when there is one.
        .padding(.bottom, selected == nil ? 0 : 96)
    }

    private var selected: MapPlaceResult? {
        guard let selectedID else { return nil }
        return places.results.first { $0.id == selectedID }
    }

    /// The camera has moved far enough from where the results were measured
    /// that they are no longer about what is on screen. Half the current
    /// radius is the same rule `RegionPlanner` uses to decide a geofence plan
    /// has gone stale, and for the same reason.
    private var pannedAway: GeoCoordinate? {
        guard let cameraCenter, cameraCenter.isValid else { return nil }
        let moved = places.distanceFromResults(to: cameraCenter)
        guard moved > places.filter.distance.meters / 2 else { return nil }
        return cameraCenter
    }

    /// Points the camera at the places, not at the radius.
    ///
    /// **Zooming to the search radius was wrong, and the first screenshots
    /// showed exactly how wrong.** A three-mile radius with everything inside
    /// the nearest half mile gave a map of the whole of Atlanta with ten pins
    /// in a heap at the middle. What somebody wants to see is the places, so
    /// the camera is fitted to them and the radius is only the fallback for
    /// when there are none yet.
    private func focusCamera() {
        guard let center = places.center else { return }
        camera = .region(fittedRegion(around: center))
        cameraCenter = nil
    }

    private func fittedRegion(around center: GeoCoordinate) -> MKCoordinateRegion {
        let middle = CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude)
        let coordinates = places.results.map(\.place.coordinate)
        guard !coordinates.isEmpty else {
            return MKCoordinateRegion(center: middle, span: span(for: places.filter.distance))
        }

        // The furthest pin in each direction, mirrored so the anchor stays in
        // the middle, with a little air around the edge. Floored at ~500m
        // across so three shops on one block do not zoom to the pavement.
        let minimum = 500 / 111_194.93
        let latitude = coordinates.map { abs($0.latitude - center.latitude) }.max() ?? 0
        let longitude = coordinates.map { abs($0.longitude - center.longitude) }.max() ?? 0
        return MKCoordinateRegion(
            center: middle,
            span: MKCoordinateSpan(
                latitudeDelta: max(latitude * 2.5, minimum),
                longitudeDelta: max(longitude * 2.5, minimum)
            )
        )
    }

    private func span(for distance: MapDistance) -> MKCoordinateSpan {
        // Twice the radius across, with a little air around the edge.
        let degrees = (distance.meters * 2.4) / 111_194.93
        return MKCoordinateSpan(latitudeDelta: degrees, longitudeDelta: degrees)
    }

    // MARK: - The list

    private var resultsList: some View {
        @Bindable var places = places

        return ScrollView {
            VStack(alignment: .leading, spacing: Metric.snug) {
                HStack(alignment: .firstTextBaseline) {
                    Text(places.resultsTitle)
                        .font(.headline)
                    Spacer(minLength: Metric.tight)
                    Menu {
                        Picker("Sort", selection: $places.filter.sort) {
                            ForEach(MapSort.allCases, id: \.self) { sort in
                                Text(sort.displayName).tag(sort)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("Sort")
                            Image(systemName: "chevron.down")
                                .font(.caption2.weight(.semibold))
                        }
                        .font(.subheadline)
                        .foregroundStyle(Color.cardWiseBlue)
                    }
                }
                .padding(.horizontal, Metric.margin)
                .padding(.top, Metric.regular)

                if places.isLoading && places.results.isEmpty {
                    loadingRow
                } else if let failure = places.failure {
                    message(symbolName: "exclamationmark.triangle", title: "Could not look up nearby places", detail: failure)
                } else if places.results.isEmpty {
                    emptyMessage
                } else {
                    LazyVStack(spacing: Metric.snug) {
                        ForEach(places.results) { result in
                            Button {
                                openPlace = result.place
                            } label: {
                                PlaceRow(result: result)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Metric.margin)
                }
            }
            .padding(.bottom, 90)
        }
    }

    private var loadingRow: some View {
        HStack(spacing: Metric.snug) {
            ProgressView()
            Text("Looking around you…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Metric.regular)
        .cardWisePanel()
        .padding(.horizontal, Metric.margin)
    }

    /// Three different silences, and they need three different sentences. A
    /// map that is blank because no key was built in looks exactly like a map
    /// that is blank because it is three in the morning in a field.
    @ViewBuilder
    private var emptyMessage: some View {
        if places.hasNoProvider {
            message(
                symbolName: "mappin.slash",
                title: "No place provider",
                detail: "This build of CardWise has nowhere to get shops from, so the map can only show where you are. Everything else in the app still works."
            )
        } else if places.center == nil {
            message(
                symbolName: "location.slash",
                title: "CardWise cannot see where you are",
                detail: "The map needs location access to know what is around you. You can turn it on under More › Settings."
            )
        } else if places.activeQuery != nil {
            message(
                symbolName: "magnifyingglass",
                title: "Nothing matched",
                detail: "No place within \(places.filter.distance.displayName) matched that. Try a wider distance, or a different word."
            )
        } else {
            message(
                symbolName: "mappin.and.ellipse",
                title: "Nothing within \(places.filter.distance.displayName)",
                detail: "Widen the distance, or turn more kinds of place back on in the filters."
            )
        }
    }

    private func message(symbolName: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: Metric.tight) {
            Label(title, systemImage: symbolName)
                .font(.subheadline.weight(.semibold))
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Metric.regular)
        .cardWisePanel()
        .padding(.horizontal, Metric.margin)
    }

    private func tint(for category: MapCategory) -> Color {
        category.benefitGroup?.tint ?? Color(red: 0.392, green: 0.455, blue: 0.545)
    }
}

// MARK: - Pieces

/// One of the map's own pins.
///
/// A teardrop rather than a plain dot so a pin reads as a place even at the
/// size the map draws it, in its category's colour so the shelf is
/// recognisable before anything is tapped, and with a ring around it when a
/// card in the wallet pays more than its everyday rate there — which is the
/// one thing on this screen worth spotting from across a map.
private struct MapPin: View {
    let category: MapCategory
    let isOpportunity: Bool
    let isSelected: Bool

    private var tint: Color {
        category.benefitGroup?.tint ?? Color(red: 0.392, green: 0.455, blue: 0.545)
    }

    private var size: CGFloat { isSelected ? 42 : 32 }

    var body: some View {
        ZStack {
            Circle()
                .fill(tint)
                .frame(width: size, height: size)
                .overlay {
                    Circle()
                        .strokeBorder(.white, lineWidth: isOpportunity ? 3 : 1.5)
                }
                .shadow(color: Color.cardWiseNavy.opacity(0.28), radius: 4, y: 2)
            Image(systemName: category.symbolName)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(.white)
        }
        .accessibilityHidden(true)
    }
}

/// A filter chip: on is filled, off is a plain capsule.
private struct FilterChip: View {
    let title: String
    let isOn: Bool
    var tint: Color = .cardWiseBlue
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(isOn ? Color.white : Color.primary)
                .padding(.horizontal, Metric.snug)
                .padding(.vertical, 7)
                .background(
                    isOn ? AnyShapeStyle(tint) : AnyShapeStyle(Color(.secondarySystemGroupedBackground)),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}

/// The card that slides up over the map when a pin is tapped.
private struct SelectedPlaceCard: View {
    let result: MapPlaceResult
    var onOpen: () -> Void
    var onDismiss: () -> Void

    /// **Not a `Button` wrapping another `Button`.** The close control is a
    /// real button and the card around it is a tap gesture, because SwiftUI
    /// routes a tap inside nested buttons to whichever one it feels like and
    /// the X would sometimes open the place instead of dismissing it.
    var body: some View {
        HStack(spacing: Metric.snug) {
            CategoryIcon(
                symbolName: result.place.mapCategory.symbolName,
                tint: result.place.mapCategory.benefitGroup?.tint ?? .secondary,
                size: 44
            )
            VStack(alignment: .leading, spacing: 3) {
                Text(result.place.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("\(result.place.subtitle) · \(result.distanceText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let reward = result.rewardLine {
                    Text(reward)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.cardWiseBlue)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: "Open", onOpen)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(Metric.snug)
        .background(.background, in: RoundedRectangle(cornerRadius: Metric.tileRadius, style: .continuous))
        .shadow(color: Color.cardWiseNavy.opacity(0.2), radius: 12, y: 4)
    }
}

/// One row of the list under the map.
///
/// **No photograph.** The mockup puts a picture of each shop here, and Google
/// will sell them — but a place photo is a separately billed request per
/// image, carries its own attribution requirement, and would be twenty of them
/// per screen. The category tile costs nothing, is legible at a glance, and is
/// the same colour the pin was, which is the actual job the picture was doing.
struct PlaceRow: View {
    let result: MapPlaceResult

    var body: some View {
        HStack(spacing: Metric.snug) {
            CategoryIcon(
                symbolName: result.place.mapCategory.symbolName,
                tint: result.place.mapCategory.benefitGroup?.tint ?? Color(red: 0.392, green: 0.455, blue: 0.545),
                size: 48
            )
            VStack(alignment: .leading, spacing: 3) {
                Text(result.place.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(result.place.subtitle)
                        .lineLimit(1)
                    Text("·")
                    Text(result.distanceText)
                        .monospacedDigit()
                    if let rating = result.place.rating {
                        Text("·")
                        Label(String(format: "%.1f", rating), systemImage: "star.fill")
                            .labelStyle(.titleAndIcon)
                            .monospacedDigit()
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Text(result.rewardLine ?? "No card in your wallet earns extra here")
                    .font(.caption.weight(result.rewardLine == nil ? .regular : .medium))
                    .foregroundStyle(result.rewardLine == nil ? Color.secondary : Color.cardWiseBlue)
                    .lineLimit(1)
            }
            Spacer(minLength: Metric.tight)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(Metric.snug)
        .cardWisePanel(radius: Metric.tileRadius)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack {
        NearbyMapView()
    }
    .environment(WalletStore.previewStore())
    .environment(NearbyPlacesStore())
}
