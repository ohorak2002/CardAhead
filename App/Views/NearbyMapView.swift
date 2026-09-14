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
    /// Only ever read, and only for one thing: which of these shops already
    /// has a geofence around it. See `watchedIDs`.
    @Environment(RegionMonitor.self) private var monitor

    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var selectedID: String?
    @State private var openPlace: MapPlace?
    @State private var isFiltering = false
    /// Where the camera is now, as opposed to where the results were measured
    /// from. The gap between the two is what raises "Search this area".
    @State private var cameraCenter: GeoCoordinate?
    /// How much ground the map is showing. Pins are grouped against this: two
    /// shops that overlap when you can see a mile do not overlap when you can
    /// see a street, so the clustering has to loosen as you zoom out.
    @State private var cameraSpan: MKCoordinateSpan?
    /// Bumped every time a cluster is opened, purely to give the haptic
    /// something to fire on. `sensoryFeedback` watches a value for a change;
    /// zooming twice into the same cluster has to feel the same as zooming
    /// into two different ones, which a counter gives and the cluster's own id
    /// would not.
    @State private var clusterOpenings = 0

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
            // CI photographs one screen per launch because `simctl` cannot
            // tap, so the watched view has to be reachable from a launch
            // argument. Same arrangement as `MoreView.startOnImpact`.
            if DemoSeed.requestedTab == "watching", !places.isShowingWatchedOnly {
                places.showWatchedOnly()
            }
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
        // **The two moments on this screen that are a gesture rather than a
        // tap on a button.** Selecting a pin is a selection, so it gets the
        // selection tick; opening a cluster moves the whole map under your
        // thumb, so it gets a light impact — the thing you feel when
        // something physical shifts. Deselecting gets nothing: closing a card
        // is not an event, and a haptic on every dismissal is how an app
        // starts feeling noisy.
        .sensoryFeedback(trigger: selectedID) { _, new in
            new == nil ? nil : .selection
        }
        .sensoryFeedback(.impact(weight: .light), trigger: clusterOpenings)
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
                        isOn: !places.isShowingWatchedOnly && places.filter.isShowingEverything,
                        tint: .cardWiseBlue
                    ) {
                        places.showEverywhere()
                        places.filter.showEverything()
                    }
                    // **Always shown, even when nothing is watched**, and that
                    // is the point rather than an oversight. "CardWise is not
                    // watching anything yet, and here is why" is precisely the
                    // answer somebody comes to this chip for when no reminder
                    // has arrived. Hiding the chip would hide the diagnosis
                    // along with the diagnostic.
                    FilterChip(
                        title: places.watchedCount > 0 ? "Watching \(places.watchedCount)" : "Watching",
                        symbolName: "bell.fill",
                        isOn: places.isShowingWatchedOnly,
                        tint: .cardWiseBlue
                    ) {
                        if places.isShowingWatchedOnly {
                            places.showEverywhere()
                        } else {
                            places.showWatchedOnly()
                        }
                    }
                    ForEach(MapCategory.quickFilters, id: \.self) { category in
                        FilterChip(
                            title: category.shortName,
                            isOn: !places.isShowingWatchedOnly
                                && !places.filter.isShowingEverything
                                && places.filter.categories == [category],
                            tint: category.mapTint
                        ) {
                            // A chip is a "show me only this" switch, and
                            // tapping the one already on goes back to
                            // everything. Ticking several at once is what the
                            // filter sheet is for.
                            //
                            // It also leaves the watched view, because the
                            // chips read as one row of alternatives and a
                            // category chip that narrowed the *watched* set
                            // while staying dim would be lying about which of
                            // them is on.
                            let wasWatching = places.isShowingWatchedOnly
                            places.showEverywhere()
                            if !wasWatching, places.filter.categories == [category] {
                                places.filter.showEverything()
                            } else {
                                places.filter.showOnly(category)
                            }
                        }
                    }
                    // Hidden in the watched view rather than shown having no
                    // effect: the geofence plan has whatever reach it has, and
                    // a control that silently does nothing is worse than one
                    // that is not there.
                    if !places.isShowingWatchedOnly {
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

    /// The shops that already have a geofence around them.
    ///
    /// Reminders arriving out of nowhere are the part of this app that feels
    /// like magic, and magic is the thing people distrust. Marking the watched
    /// shops turns "how did it know?" into "of course, it said so".
    private var watchedIDs: Set<String> {
        monitor.plan?.watchedPlaceIDs ?? []
    }

    /// Pins, grouped so they cannot sit on top of each other.
    ///
    /// The grouping distance comes from the camera rather than a constant: a
    /// pin is about 40 points across and the map is 300 points tall, so two
    /// pins are touching when they are closer than `40/300` of whatever the
    /// map is currently showing. Zoom in and the same two shops come apart on
    /// their own.
    private var pinGroups: [MapPinGroup] {
        let latitudeDelta = cameraSpan?.latitudeDelta ?? span(for: places.filter.distance).latitudeDelta
        let separation = (NearbyPlaces.pinDiameterPoints / Double(Self.mapHeight)) * latitudeDelta
        return NearbyPlaces.pinGroups(
            for: places.results,
            separationDegrees: separation,
            referenceLatitude: places.center?.latitude ?? 0
        )
    }

    private var map: some View {
        ZStack(alignment: .bottom) {
            Map(position: $camera) {
                UserAnnotation()
                ForEach(pinGroups) { group in
                    Annotation(
                        group.id,
                        coordinate: CLLocationCoordinate2D(
                            latitude: group.coordinate.latitude,
                            longitude: group.coordinate.longitude
                        ),
                        anchor: .center
                    ) {
                        // **A button rather than `Map(selection:)`.** A tap on
                        // a cluster has to zoom and a tap on a single shop has
                        // to select it; one selection binding cannot say which
                        // happened, and working it back out of the tag was two
                        // code paths that had to agree with each other.
                        Button {
                            tap(group)
                        } label: {
                            MapPin(
                                group: group,
                                isSelected: selectedID == group.id,
                                isWatched: isWatched(group)
                            )
                        }
                        .buttonStyle(.plain)
                    }
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
                cameraSpan = context.region.span
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
                    SelectedPlaceCard(
                        result: selected,
                        isWatched: watchedIDs.contains(selected.place.id)
                    ) {
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

    private func isWatched(_ group: MapPinGroup) -> Bool {
        let watched = watchedIDs
        guard !watched.isEmpty else { return false }
        return group.results.contains { watched.contains($0.place.id) }
    }

    /// A single shop selects; a heap of them zooms until it is not a heap.
    private func tap(_ group: MapPinGroup) {
        guard group.isCluster else {
            selectedID = group.id
            return
        }
        selectedID = nil
        clusterOpenings += 1
        // Enough to pull the members apart, floored so a pair of shops in the
        // same building does not zoom to the doorstep.
        let minimum = 250 / 111_194.93
        camera = .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: group.coordinate.latitude,
                longitude: group.coordinate.longitude
            ),
            span: MKCoordinateSpan(
                latitudeDelta: max(group.latitudeSpread * 3, minimum),
                longitudeDelta: max(group.longitudeSpread * 3, minimum)
            )
        ))
    }

    private var selected: MapPlaceResult? {
        guard let selectedID else { return nil }
        return pinGroups.first { $0.id == selectedID }?.single
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
        let region = fittedRegion(around: center)
        camera = .region(region)
        cameraCenter = nil
        cameraSpan = region.span
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
                    resultRows
                }
            }
            .padding(.bottom, 90)
        }
    }

    private var resultRows: some View {
        // Read once rather than per row: it walks the whole region plan.
        let watched = watchedIDs
        return LazyVStack(spacing: Metric.snug) {
            ForEach(places.results) { result in
                Button {
                    openPlace = result.place
                } label: {
                    PlaceRow(result: result, isWatched: watched.contains(result.place.id))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Metric.margin)
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

    /// Four different silences, and they need four different sentences. A map
    /// that is blank because no key was built in looks exactly like a map that
    /// is blank because it is three in the morning in a field.
    ///
    /// Two of the four are a filter set too narrowly, and those two carry the
    /// way out as a button. Telling somebody what to do and leaving them to go
    /// and find it is the kind of empty state that reads as an apology.
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
        } else if places.isShowingWatchedOnly {
            // The most useful empty state in the app: somebody who has had no
            // reminders and wants to know whether that is restraint or a
            // broken permission. Every reason listed is one this app can
            // actually be in, and each names the screen that fixes it.
            message(
                symbolName: "bell.slash",
                title: "Not watching anything yet",
                detail: "Geofences are registered once there is a card with a bonus category in your wallet, Always location is granted, and CardWise has had a location fix. More › Settings › Reminder activity says which of those is missing."
            ) {
                Button("Show everywhere") { places.showEverywhere() }
                    .buttonStyle(.borderedProminent)
            }
        } else if places.activeQuery != nil {
            message(
                symbolName: "magnifyingglass",
                title: "Nothing matched",
                detail: "No place within \(places.filter.distance.displayName) matched that."
            ) {
                widenButton
                Button("Clear the search") { places.clearSearch() }
                    .buttonStyle(.bordered)
            }
        } else {
            message(
                symbolName: "mappin.and.ellipse",
                title: "Nothing within \(places.filter.distance.displayName)",
                detail: "Nothing of the kind you asked for is in range."
            ) {
                widenButton
                if !places.filter.isShowingEverything {
                    Button("Show every kind of place") { places.filter.showEverything() }
                        .buttonStyle(.bordered)
                }
            }
        }
    }

    /// Widens to the next step out. Absent at ten miles, because a button that
    /// does nothing is worse than no button.
    @ViewBuilder
    private var widenButton: some View {
        if let wider = nextDistanceOut {
            Button("Widen to \(wider.displayName)") {
                places.filter.distance = wider
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var nextDistanceOut: MapDistance? {
        let all = MapDistance.allCases
        guard let index = all.firstIndex(of: places.filter.distance),
              index + 1 < all.count
        else { return nil }
        return all[index + 1]
    }

    private func message<Actions: View>(
        symbolName: String,
        title: String,
        detail: String,
        @ViewBuilder actions: () -> Actions = { EmptyView() }
    ) -> some View {
        VStack(alignment: .leading, spacing: Metric.tight) {
            Label(title, systemImage: symbolName)
                .font(.subheadline.weight(.semibold))
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Metric.tight) {
                actions()
            }
            .font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Metric.regular)
        .cardWisePanel()
        .padding(.horizontal, Metric.margin)
    }
}

// MARK: - Pieces

extension Color {
    /// The slate `MapCategory.other` wears, since it has no benefit shelf to
    /// borrow a colour from. Declared once so three views cannot drift.
    static let mapOther = Color(red: 0.392, green: 0.455, blue: 0.545)
}

extension MapCategory {
    var mapTint: Color { benefitGroup?.tint ?? .mapOther }
}

/// One of the map's own pins, standing for one shop or for several.
///
/// Three things are readable without tapping anything: what kind of place it
/// is (the colour and the symbol), whether a card in the wallet beats its
/// everyday rate there (the thick white ring), and whether CardWise is already
/// watching it for you (the small bell). A cluster shows a count instead of a
/// symbol, in the colour of whatever it is mostly made of.
private struct MapPin: View {
    let group: MapPinGroup
    let isSelected: Bool
    let isWatched: Bool

    private var tint: Color { group.dominantCategory.mapTint }

    private var size: CGFloat {
        if group.isCluster { return isSelected ? 48 : 42 }
        return isSelected ? 42 : 32
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(tint)
                .frame(width: size, height: size)
                .overlay {
                    Circle()
                        .strokeBorder(.white, lineWidth: group.hasOpportunity ? 3 : 1.5)
                }
                .shadow(color: Color.cardWiseNavy.opacity(0.28), radius: 4, y: 2)

            if group.isCluster {
                Text("\(group.count)")
                    .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            } else {
                Image(systemName: group.dominantCategory.symbolName)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
            }

            if isWatched {
                Image(systemName: "bell.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 16, height: 16)
                    .background(.white, in: Circle())
                    .offset(x: size * 0.38, y: -size * 0.38)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(label)
    }

    private var label: String {
        var words = group.isCluster
            ? "\(group.count) places"
            : (group.single?.place.name ?? "A place")
        if group.hasOpportunity { words += ", a card here pays more than usual" }
        if isWatched { words += ", being watched for a reminder" }
        return words
    }
}

/// A filter chip: on is filled, off is a plain capsule.
private struct FilterChip: View {
    let title: String
    /// Only the Watching chip has one. A row of chips that all carry a symbol
    /// reads as a toolbar; one that carries a symbol among plain ones reads as
    /// the odd one out, which is exactly what it is.
    var symbolName: String?
    let isOn: Bool
    var tint: Color = .cardWiseBlue
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbolName {
                    Image(systemName: symbolName)
                        .font(.caption2.weight(.semibold))
                }
                Text(title)
            }
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
    var isWatched: Bool
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
                tint: result.place.mapCategory.mapTint,
                size: 44
            )
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(result.place.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if isWatched { WatchingMark() }
                }
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
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: Metric.tileRadius, style: .continuous))
        .shadow(color: Color.cardWiseNavy.opacity(0.2), radius: 12, y: 4)
    }
}

/// The bell that means "a reminder is already set up for this shop".
///
/// One glyph on the map and on a row, a whole sentence on the place detail —
/// which is the only one of the three where somebody has time to read one.
struct WatchingMark: View {
    var body: some View {
        Image(systemName: "bell.fill")
            .font(.caption2)
            .foregroundStyle(Color.cardWiseBlue)
            .accessibilityLabel("CardWise is watching this place")
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
    var isWatched: Bool = false

    var body: some View {
        HStack(spacing: Metric.snug) {
            CategoryIcon(
                symbolName: result.place.mapCategory.symbolName,
                tint: result.place.mapCategory.mapTint,
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
            VStack(spacing: 6) {
                if isWatched { WatchingMark() }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
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
    .environment(RegionMonitor())
}
