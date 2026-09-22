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
/// ## The screen was rebuilt, and this is what changed
///
/// It used to be a navy header, a search field, a row of chips, a map inset
/// into a rounded rectangle, and a list of cards under it — a vertical stack
/// in which the map got about a quarter of the screen. Everything on it was
/// correct and the whole was wrong: **the tab named Map was mostly not a
/// map.** A map you cannot see is a picture of a map.
///
/// So the map is now the screen, edge to edge, and everything else floats over
/// it: the search field and the chips at the top, the results in a sheet that
/// pulls up from the bottom. That costs the shared navy `ScreenHeader` this
/// app wears everywhere else, which is a real loss of family resemblance and
/// worth it exactly once — a title bar over a map is 190 points spent saying
/// the word "Map" above a map. The brand stays visible where it does work:
/// the pins, the chips, and the one blue line in every row that says which
/// card wins.
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
    /// How much room the whole tab has. Feeds the sheet's three heights and
    /// the pin clustering, both of which used to be measured against a map
    /// that had a fixed height of its own.
    @State private var availableHeight: CGFloat = 700
    @State private var detent: CardWiseSheetDetent = .half

    var body: some View {
        @Bindable var places = places

        // **A `GeometryReader` at the root, which is not the trap it looks
        // like.** The warning written on the wallet stack is about measuring a
        // container to size something *inside* it when that container's size
        // comes from its children — VStack width from children, children sized
        // from the measurement, round and round. This is the other case: a
        // `GeometryReader` takes all the space offered to it and reports that,
        // whatever its children do.
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                mapLayer
                floatingControls
                sheetLayer
            }
            .onChange(of: proxy.size.height, initial: true) { _, height in
                availableHeight = height
            }
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
            if DemoSeed.requestedTab == "mapfilters" { isFiltering = true }
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
        // **Two screens CI could not otherwise reach.** The selected-place
        // card and the place detail are both a tap on a pin away, and `simctl`
        // cannot tap a pin — so without this they would be the two newest
        // surfaces in the app and the only ones nobody had ever seen. Same
        // arrangement as `WalletTab`'s two card-art screens.
        //
        // Driven off `results.count` rather than `onAppear` because the seeded
        // lookup answers a moment after this view exists, and a pin cannot be
        // selected before there are any.
        .onChange(of: places.results.count, initial: true) { _, _ in
            guard let wanted = DemoSeed.requestedTab else { return }
            guard let first = pinGroups.first(where: { !$0.isCluster }) else { return }
            switch wanted {
            case "placecard" where selectedID == nil:
                selectedID = first.id
                detent = .half
            case "placedetail" where openPlace == nil:
                openPlace = first.single?.place
            default: break
            }
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

    // MARK: - The map, which is now the screen

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
    /// The grouping distance comes from the camera *and* the height the map is
    /// drawn at: a pin is about 40 points across, so two pins are touching
    /// when they are closer than `40 / height` of whatever the map is
    /// currently showing. Zoom in and the same two shops come apart on their
    /// own.
    private var pinGroups: [MapPinGroup] {
        let latitudeDelta = cameraSpan?.latitudeDelta ?? span(for: places.filter.distance).latitudeDelta
        let separation = (NearbyPlaces.pinDiameterPoints / Double(max(availableHeight, 1))) * latitudeDelta
        return NearbyPlaces.pinGroups(
            for: places.results,
            separationDegrees: separation,
            referenceLatitude: places.center?.latitude ?? 0
        )
    }

    private var mapLayer: some View {
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
                    // **A button rather than `Map(selection:)`.** A tap on a
                    // cluster has to zoom and a tap on a single shop has to
                    // select it; one selection binding cannot say which
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
        // Edge to edge, under the status bar and under the sheet. The map is
        // the ground everything else on this screen stands on.
        .ignoresSafeArea()
    }

    // MARK: - What floats over it

    /// The search field, the chips, and the filter button.
    ///
    /// **Translucent, not solid.** The whole argument for floating a control
    /// over the map instead of putting it in a bar is that the map stays
    /// visible underneath; a control filled with the page's own colour is a
    /// bar with extra steps. See `ControlGround`.
    private var floatingControls: some View {
        @Bindable var places = places

        return VStack(spacing: Metric.tight) {
            HStack(spacing: Metric.tight) {
                Text("Nearby map")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(InterfacePalette.ink)
                Spacer(minLength: Metric.tight)
                Button {
                    isFiltering = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.headline)
                        .foregroundStyle(InterfacePalette.blue)
                        .frame(width: 44, height: 44)
                        .background(InterfacePalette.wash, in: Circle())
                }
                .accessibilityLabel("Filters")
            }
            .padding(.horizontal, Metric.margin)

            CardWiseSearchField(
                placeholder: "Search places, stores or categories",
                text: $places.searchText,
                onSubmit: { places.runSearch() },
                onClear: { places.clearSearch() },
                ground: .tinted
            )
            .padding(.horizontal, Metric.margin)

            HStack {
                Text(places.activeQuery.map { "Results for \"\($0)\" · \(places.filter.distance.shortName) from search center" } ?? places.filter.summary)
                    .font(.caption).foregroundStyle(.secondary)
                if places.activeQuery != nil { Button("Cancel search") { places.clearSearch() } }
            }.padding(.horizontal, Metric.margin)
            chips
        }
        .padding(.top, Metric.tight)
        .padding(.bottom, Metric.tight)
        .background { InterfacePalette.page.ignoresSafeArea(edges: .top) }
    }

    private var chips: some View {
        @Bindable var places = places

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Metric.tight) {
                CardWiseChip(
                    title: "All",
                    isOn: !places.isShowingWatchedOnly && places.filter.isShowingEverything,
                    tint: .cardWiseBlue,
                    ground: .tinted
                ) {
                    places.showEverywhere()
                    places.filter.toggleAll()
                }
                // **Always shown, even when nothing is watched**, and that is
                // the point rather than an oversight. "CardWise is not
                // watching anything yet, and here is why" is precisely the
                // answer somebody comes to this chip for when no reminder has
                // arrived. Hiding the chip would hide the diagnosis along with
                // the diagnostic.
                CardWiseChip(
                    title: places.watchedCount > 0 ? "Watching \(places.watchedCount)" : "Watching",
                    symbolName: "bell.fill",
                    isOn: places.isShowingWatchedOnly,
                    tint: .cardWiseBlue,
                    ground: .tinted
                ) {
                    if places.isShowingWatchedOnly {
                        places.showEverywhere()
                    } else {
                        places.showWatchedOnly()
                    }
                }
                ForEach(MapCategory.quickFilters, id: \.self) { category in
                    CardWiseChip(
                        title: category.shortName,
                        isOn: !places.isShowingWatchedOnly
                            && !places.filter.isShowingEverything
                            && places.filter.categories.contains(category),
                        tint: category.mapTint,
                        ground: .tinted
                    ) {
                        // A chip is a "show me only this" switch, and tapping
                        // the one already on goes back to everything. Ticking
                        // several at once is what the filter sheet is for.
                        //
                        // It also leaves the watched view, because the chips
                        // read as one row of alternatives and a category chip
                        // that narrowed the *watched* set while staying dim
                        // would be lying about which of them is on.
                        places.showEverywhere()
                        places.filter.toggle(category)
                    }
                }
                // Hidden in the watched view rather than shown having no
                // effect: the geofence plan has whatever reach it has, and a
                // control that silently does nothing is worse than one that is
                // not there.
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
                        .background(InterfacePalette.wash, in: Capsule())
                        .frame(minHeight: Metric.minimumTarget)
                    }
                }
            }
            .padding(.horizontal, Metric.regular)
            // The shadows on the chips are clipped by the scroll view without
            // this: a horizontal scroll view clips to its own bounds, and the
            // bounds are exactly the chips' height.
            .padding(.vertical, 6)
        }
        .scrollClipDisabled()
    }

    // MARK: - The sheet, and what sits just above it

    private var sheetLayer: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            HStack(alignment: .bottom) {
                if let panned = pannedAway {
                    Button {
                        places.searchArea(around: panned)
                        cameraCenter = nil
                    } label: {
                        Label("Search this area", systemImage: "arrow.clockwise")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, Metric.regular)
                            .padding(.vertical, 10)
                            .background(.regularMaterial, in: Capsule())
                            .shadow(color: Color.cardWiseNavy.opacity(0.18), radius: 10, y: 3)
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                }
                Spacer(minLength: Metric.tight)
                recenterButton
            }
            .padding(.horizontal, Metric.regular)
            .padding(.bottom, Metric.snug)

            CardWiseBottomSheet(detent: $detent, availableHeight: availableHeight) {
                sheetContent
            }
        }
        .animation(.snappy(duration: 0.25), value: selectedID)
        .animation(.snappy(duration: 0.25), value: pannedAway != nil)
    }

    private var recenterButton: some View {
        Button {
            places.recenterOnUser()
        } label: {
            Image(systemName: "location.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.cardWiseBlue)
                .frame(width: 44, height: 44)
                .background(.regularMaterial, in: Circle())
                .shadow(color: Color.cardWiseNavy.opacity(0.18), radius: 10, y: 3)
        }
        .accessibilityLabel("Back to my location")
    }

    /// Either the place you tapped, or everything nearby.
    ///
    /// **One surface, not two.** The old screen put a small selected-place
    /// card over the map *and* kept the list underneath, which meant two
    /// answers to the same question on screen at once and the card covering
    /// the pin it described. Selecting a place now replaces the list with it,
    /// the way every map application does, and closing it puts the list back.
    @ViewBuilder
    private var sheetContent: some View {
        if let selected {
            ScrollView {
                MerchantPlaceCard(
                    result: selected,
                    isWatched: watchedIDs.contains(selected.place.id),
                    onOpen: { openPlace = selected.place },
                    onDismiss: { selectedID = nil }
                )
                // Clears the floating tab bar the sheet now runs behind.
                .padding(.bottom, 90)
            }
            .scrollBounceBehavior(.basedOnSize)
        } else {
            resultsList
        }
    }

    // MARK: - The list

    private var resultsList: some View {
        @Bindable var places = places

        return VStack(spacing: 0) {
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
            .padding(.bottom, Metric.tight)

            ScrollView {
                if places.isLoading && places.results.isEmpty {
                    loadingRow
                } else if let failure = places.failure {
                    CardWiseEmptyState(
                        symbolName: "exclamationmark.triangle",
                        title: "We couldn't load nearby places",
                        message: failure
                    ) {
                        Button("Try again") { places.refresh() }
                            .buttonStyle(CardWiseSecondaryButtonStyle())
                    }
                } else if places.results.isEmpty {
                    emptyMessage
                } else {
                    resultRows
                }
            }
        }
        .padding(.bottom, Metric.tight)
    }

    private var resultRows: some View {
        // Read once rather than per row: it walks the whole region plan.
        let watched = watchedIDs
        let results = places.results
        return LazyVStack(spacing: 0) {
            ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                Button {
                    openPlace = result.place
                } label: {
                    MerchantRow(
                        result: result,
                        isWatched: watched.contains(result.place.id),
                        showsSeparator: index < results.count - 1
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Metric.margin)
        // Clears the floating tab bar, which content passes under on iOS 26.
        .padding(.bottom, 90)
    }

    private var loadingRow: some View {
        VStack(spacing: 0) {
            // Three rows the shape of the real thing, rather than a spinner in
            // the middle of a blank panel: the list does not jump when the
            // places land, and the wait looks like the thing being waited for.
            ForEach(0..<3, id: \.self) { index in
                HStack(spacing: Metric.snug) {
                    RoundedRectangle(cornerRadius: Metric.tileRadius, style: .continuous)
                        .fill(Color.cardWiseHairline.opacity(0.6))
                        .frame(width: 68, height: 68)
                    VStack(alignment: .leading, spacing: 8) {
                        Capsule().fill(Color.cardWiseHairline.opacity(0.6)).frame(width: 150, height: 12)
                        Capsule().fill(Color.cardWiseHairline.opacity(0.45)).frame(width: 100, height: 10)
                        Capsule().fill(Color.cardWiseHairline.opacity(0.45)).frame(width: 130, height: 10)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, Metric.snug)
                if index < 2 {
                    Hairline(inset: 68 + Metric.snug)
                }
            }
        }
        .padding(.horizontal, Metric.margin)
        .accessibilityElement()
        .accessibilityLabel("Looking around you")
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
        if places.filter.isShowingNothing {
            CardWiseEmptyState(symbolName: "line.3.horizontal.decrease.circle", title: "Select a category to see nearby places", message: "Choose All or one or more categories above.")
        } else if places.hasNoProvider {
            CardWiseEmptyState(
                symbolName: "mappin.slash",
                title: "No place provider",
                message: "This build of CardWise has nowhere to get shops from, so the map can only show where you are. Everything else in the app still works."
            )
        } else if places.center == nil {
            CardWiseEmptyState(
                symbolName: "location.slash",
                title: "CardWise cannot see where you are",
                message: "The map needs location access to know what is around you. You can turn it on under More › Settings."
            )
        } else if places.isShowingWatchedOnly {
            CardWiseEmptyState(
                symbolName: "bell.slash",
                title: "Nothing being watched yet",
                message: "CardWise watches up to twenty nearby shops where one of your cards pays more than usual. Add a card, or move around a little, and they will appear here."
            ) {
                Button("Show everything nearby") { places.showEverywhere() }
                    .buttonStyle(CardWiseSecondaryButtonStyle())
            }
        } else {
            CardWiseEmptyState(
                symbolName: "mappin.and.ellipse",
                title: "Nothing nearby",
                message: "No places matched here. Try a wider distance, or a different category."
            ) {
                Button("Show everything nearby") {
                    places.showEverywhere()
                    places.filter.showEverything()
                }
                .buttonStyle(CardWiseSecondaryButtonStyle())
            }
        }
    }

    // MARK: - Behaviour

    private func isWatched(_ group: MapPinGroup) -> Bool {
        let watched = watchedIDs
        guard !watched.isEmpty else { return false }
        return group.results.contains { watched.contains($0.place.id) }
    }

    /// A single shop selects; a heap of them zooms until it is not a heap.
    private func tap(_ group: MapPinGroup) {
        guard group.isCluster else {
            selectedID = group.id
            // A selected place needs room to be read, and the peek height
            // shows only its photograph. Never *shrinks* the sheet, though:
            // somebody who pulled it all the way up did that on purpose.
            if detent == .peek { detent = .half }
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
        //
        // **Weighted downward**, because the bottom half of the map is behind
        // the sheet. Fitting pins to the whole map and then covering half of
        // it with a sheet hides half the pins.
        let minimum = 500 / 111_194.93
        let latitude = coordinates.map { abs($0.latitude - center.latitude) }.max() ?? 0
        let longitude = coordinates.map { abs($0.longitude - center.longitude) }.max() ?? 0

        // The sheet covers the bottom half at its resting height, so the pins
        // are fitted into the *top* half: the span is widened to make room,
        // and the camera's centre is then moved south of the anchor by a
        // quarter of it, which lifts everything into the part you can see.
        // Fitting to the whole map and then covering half of it is how you
        // end up with a well-framed map of pins nobody can see.
        let latitudeSpan = max(latitude * 2.5, minimum) * 1.6
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: center.latitude - latitudeSpan * 0.25,
                longitude: center.longitude
            ),
            span: MKCoordinateSpan(
                latitudeDelta: latitudeSpan,
                longitudeDelta: max(longitude * 2.5, minimum)
            )
        )
    }

    private func span(for distance: MapDistance) -> MKCoordinateSpan {
        // Twice the radius across, with a little air around the edge.
        let degrees = (distance.meters * 2.4) / 111_194.93
        return MKCoordinateSpan(latitudeDelta: degrees, longitudeDelta: degrees)
    }
}

// MARK: - Pieces

extension Color {
    /// The slate `MapCategory.other` wears, since it has no benefit shelf to
    /// borrow a colour from. Declared once so three views cannot drift.
    ///
    /// Borrowed from "Everything else", which is the same idea one layer up —
    /// and taken from the palette rather than retyped as a literal, so it is
    /// covered by `BrandTintTests` like every other tint.
    static let mapOther = BenefitGroup.everydaySpending.tint
    /// The same slate for a solid pin. See `BrandTint.solid`.
    static let mapOtherPin = BenefitGroup.everydaySpending.pinTint
}

extension MapCategory {
    /// A **solid pin** with a white symbol on it, so it takes `pinTint` and
    /// not `tint` — see `BrandTint.solid` for why those differ.
    var mapTint: Color { benefitGroup?.pinTint ?? .mapOtherPin }
    /// A glyph on the page, in a list or a filter row, which does follow the
    /// interface style.
    var listTint: Color { benefitGroup?.tint ?? .mapOther }
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tint: Color { group.dominantCategory.mapTint }

    private var size: CGFloat {
        if group.isCluster { return isSelected ? 48 : 42 }
        return isSelected ? 44 : 32
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
        // The selected pin grows, which is how you find it again after the
        // sheet has covered half the map. Motion, so Reduce Motion turns it
        // into an instant change of size rather than a spring.
        .animation(
            reduceMotion
                ? Animation?.none
                : Animation.spring(response: 0.28, dampingFraction: 0.7),
            value: isSelected
        )
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

#Preview {
    NavigationStack {
        NearbyMapView()
    }
    .environment(WalletStore.previewStore())
    .environment(NearbyPlacesStore())
    .environment(RegionMonitor())
}
