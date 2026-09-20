import CoreLocation
import Foundation
import Observation
import os
import CardKit

/// Everything the Map tab is looking at: where it is centred, what it asked
/// for, what came back, and what went wrong.
///
/// **This is a foreground thing, and that is the whole difference between it
/// and `RegionMonitor`.** The monitor runs while the app is dead, has to
/// survive being killed between an entry and its confirmation, and writes
/// every interesting moment to disk because nobody is watching. Nothing here
/// needs any of that: a person is holding the phone and looking at the screen,
/// so a failed lookup is shown to them rather than logged for later, and
/// results live in memory and are re-fetched on the next launch.
///
/// It keeps its own `CLLocationManager`, which makes three in the app. That is
/// deliberate rather than sloppy: `LocationAuthorization` owns the permission
/// ladder and vends no coordinates, `RegionMonitor` owns significant-change
/// and geofences and must not have its settings disturbed by a map, and this
/// wants one accurate fix on demand while the screen is open. A manager is
/// cheap; sharing one between three jobs with three different accuracy and
/// lifetime requirements is not.
@Observable
final class NearbyPlacesStore: NSObject, CLLocationManagerDelegate {

    // MARK: - What the screen shows

    /// Where the results were measured from. Nil until the first fix, or
    /// until somebody pans and asks to search a new area.
    private(set) var center: GeoCoordinate?
    /// The phone's own position, kept apart from `center` so "recentre" has
    /// somewhere to go back to after a pan.
    private(set) var userLocation: GeoCoordinate?
    private(set) var places: [MapPlace] = []
    private(set) var isLoading = false
    /// Said on the screen, not swallowed into a log. A map that is empty
    /// because a lookup was refused looks exactly like a map that is empty
    /// because nothing is nearby, and those need different answers from the
    /// person holding the phone.
    private(set) var failure: String?

    var filter: MapFilter {
        didSet {
            guard filter != oldValue else { return }
            save()
            // A different radius or a different set of chips is a different
            // question for the provider, not just a different filter over
            // what is already here.
            if filter.distance != oldValue.distance || filter.effectiveCategories != oldValue.effectiveCategories {
                refresh()
            }
        }
    }

    /// What is typed in the search box.
    ///
    /// Searching is explicit — on submit, or on the clear button — rather than
    /// on every keystroke. A text search is a billed request, and "Sta" is not
    /// a question anybody meant to ask.
    var searchText = ""
    /// The query the results on screen actually answer, which is nil while
    /// browsing. Kept apart from `searchText` so a half-typed word does not
    /// make the list claim to be something it is not.
    private(set) var activeQuery: String?

    /// Showing only the shops that already have a geofence.
    ///
    /// **Deliberately not part of `MapFilter`, and deliberately not
    /// persisted.** This is a "show me what you are up to" view, not a taste:
    /// somebody who leaves it on and opens the app three days later, after the
    /// plan has been redrawn somewhere else, would be greeted by an empty map
    /// and no clue why. It resets with the process, which is the right
    /// lifetime for a diagnostic.
    var isShowingWatchedOnly = false

    // MARK: - Collaborators

    @ObservationIgnored private let source: PlaceSearchSource
    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private let log = Logger(subsystem: AppLog.subsystem, category: "map")
    @ObservationIgnored private var requestGate = PlaceRequestGate()
    @ObservationIgnored private var inFlight: Task<Void, Never>?

    /// The wallet, read rather than held — the same arrangement `RegionMonitor`
    /// uses, so a card added elsewhere is picked up at the moment the list is
    /// next built rather than needing to be pushed in.
    @ObservationIgnored var walletCards: () -> [Card] = { [] }

    /// The shops that already have a geofence, read the same way.
    ///
    /// Wired in `CardWiseApp` to `RegionMonitor.plan?.watchedPlaces`. Reading
    /// it rather than holding it keeps the two objects uncoupled — and
    /// because the read happens inside `results`, which is evaluated while a
    /// view body is running, `@Observable` still tracks the monitor's plan
    /// through it and the map redraws when the geofences change.
    @ObservationIgnored var watchedPlaces: () -> [MapPlace] = { [] }

    var sourceDescription: String { source.sourceDescription }
    /// True when the app has nowhere at all to get places from, which is a
    /// different sentence on screen from "nothing is nearby".
    var hasNoProvider: Bool { source is EmptyPlaceSearchSource }

    private static let filterDefaultsKey = "mapFilter"

    /// `initialCenter` is for the seeded screenshot run and nothing else. A
    /// simulator has no location unless somebody sets one, so without a corner
    /// to stand on CI would photograph a map of the open ocean. See `DemoSeed`.
    init(
        source: PlaceSearchSource = EmptyPlaceSearchSource(),
        filter: MapFilter? = nil,
        initialCenter: GeoCoordinate? = nil
    ) {
        self.source = source
        self.filter = filter ?? Self.loadFilter()
        self.center = initialCenter
        super.init()
        manager.delegate = self
        // A map wants a better fix than a geofence plan does, and only wants
        // it while the screen is open.
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        if initialCenter != nil { refresh() }
    }

    // MARK: - Location

    /// Called when the tab appears. Safe to call repeatedly.
    ///
    /// A map only needs **When In Use**, which is the permission the app has
    /// already asked for on the way to Always — so this never prompts for
    /// anything new, and the map keeps working for somebody who granted the
    /// lesser permission and declined the scarier one.
    func start() {
        // A seeded run already knows where it is standing, and a permission
        // dialog thrown up over the screen is the one thing that would ruin
        // every screenshot taken after it.
        guard !DemoSeed.isActive else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            break
        }
    }

    /// Puts the anchor back on the phone and asks again from there.
    func recenterOnUser() {
        guard let userLocation else {
            start()
            return
        }
        center = userLocation
        refresh()
    }

    /// How far the map has been panned from where the results were measured.
    /// The map offers "Search this area" past a threshold rather than
    /// re-querying on every pan — each query is billed, and a map that
    /// reloads under a moving thumb is unusable anyway.
    func distanceFromResults(to coordinate: GeoCoordinate) -> Double {
        guard let center else { return .greatestFiniteMagnitude }
        return center.distance(to: coordinate)
    }

    func searchArea(around coordinate: GeoCoordinate) {
        guard coordinate.isValid else { return }
        center = coordinate
        refresh()
    }

    // MARK: - Looking things up

    func refresh() {
        inFlight?.cancel()
        let token = requestGate.invalidate()
        places = []
        failure = nil
        isLoading = false
        guard !filter.isShowingNothing, !isShowingWatchedOnly else { return }
        guard let center else {
            start()
            return
        }
        let query = activeQuery
        let requestedFilter = filter
        inFlight?.cancel()
        isLoading = true
        failure = nil

        inFlight = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { if self.requestGate.accepts(token) { self.isLoading = false } }
            do {
                let found: [MapPlace]
                if let query {
                    found = try await self.source.places(
                        matching: query,
                        near: center,
                        radiusMeters: requestedFilter.distance.meters
                    )
                } else {
                    found = try await self.source.places(
                        near: center,
                        radiusMeters: requestedFilter.distance.meters,
                        categories: requestedFilter.effectiveCategories
                    )
                }
                guard !Task.isCancelled, self.requestGate.accepts(token) else { return }
                self.places = found
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, self.requestGate.accepts(token) else { return }
                self.log.error("place lookup failed: \(error.localizedDescription, privacy: .public)")
                self.failure = Self.sentence(for: error)
            }
        }
    }

    /// Runs whatever is in the search box.
    func runSearch() {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            activeQuery = nil
            refresh()
            return
        }
        guard activeQuery != trimmed || failure != nil else { return }
        isShowingWatchedOnly = false
        activeQuery = trimmed
        refresh()
    }

    func clearSearch() {
        searchText = ""
        activeQuery = nil
        refresh()
    }

    /// Fills in the fields only a details lookup pays for, and folds them onto
    /// the row the list already has so nothing the search found is lost.
    ///
    /// Returns the place unchanged when the lookup fails: a detail screen with
    /// no phone number on it is worth more than an error where the screen
    /// should be.
    func loadDetails(for place: MapPlace) async -> MapPlace {
        do {
            let detail = try await source.details(forPlaceID: place.id)
            let merged = place.merging(detail)
            if let index = places.firstIndex(where: { $0.id == place.id }) {
                places[index] = merged
            }
            return merged
        } catch {
            log.notice("no details for \(place.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return place
        }
    }

    // MARK: - The list

    /// Filtered, measured against the wallet and put in order — all of it in
    /// `CardKit`, so the part that could be wrong is tested on Linux and what
    /// is left here is a view drawing pins.
    ///
    /// The watched view reads a **different source**, not a filter over this
    /// one: see `RegionPlan.watchedPlaces` for why those two sets differ and
    /// why filtering would under-report. It also ignores the radius, because a
    /// geofence four miles out is still one of the twenty being watched.
    var results: [MapPlaceResult] {
        guard let center else { return [] }
        return NearbyPlaces.results(
            from: isShowingWatchedOnly ? watchedPlaces() : places,
            near: center,
            cards: walletCards(),
            filter: filter,
            ignoringDistance: isShowingWatchedOnly
        )
    }

    /// How many shops have a geofence right now, whatever the map is showing.
    /// The chip says this out loud so tapping it is never a surprise.
    var watchedCount: Int { watchedPlaces().count }

    var opportunityCount: Int { NearbyPlaces.opportunityCount(in: results) }

    func showEverywhere() {
        isShowingWatchedOnly = false
        refresh()
    }

    func showWatchedOnly() {
        isShowingWatchedOnly = true
        // Every watched shop, not "the watched restaurants". Somebody opening
        // this is asking what the app is up to, and an answer narrowed by a
        // chip they set ten minutes ago for another reason would under-report
        // — which is the exact failure this view exists to avoid.
        filter.showEverything()
        // Nothing to fetch: the plan is already on disk. This is the one view
        // in the whole feature that costs no lookup at all.
        activeQuery = nil
        searchText = ""
    }

    /// What the header over the list says. Named after the single chip when
    /// exactly one is on, because "Restaurants (24)" tells you more than
    /// "24 places" does.
    var resultsTitle: String {
        let count = results.count
        if isShowingWatchedOnly {
            return count == 1 ? "Watching 1 place" : "Watching \(count) places"
        }
        if filter.categories.count == 1, let only = filter.categories.first {
            return "\(only.displayName) (\(count))"
        }
        return count == 1 ? "1 place nearby" : "\(count) places nearby"
    }

    // MARK: - Persistence

    /// `UserDefaults` rather than a file of its own: this is a preference,
    /// it is three fields, and losing it costs somebody two taps. The things
    /// that get files are the things that would cost real information.
    private static func loadFilter() -> MapFilter {
        guard let data = UserDefaults.standard.data(forKey: filterDefaultsKey),
              let decoded = try? JSONDecoder().decode(MapFilter.self, from: data)
        else { return .standard }
        return decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(filter) else { return }
        UserDefaults.standard.set(data, forKey: Self.filterDefaultsKey)
    }

    // MARK: - Saying what went wrong

    /// Plain words, in the app's own register. `localizedDescription` on a
    /// `PlacesError` is "The operation couldn't be completed", which tells
    /// nobody anything.
    private static func sentence(for error: Error) -> String {
        guard let places = error as? PlacesError else {
            return "Could not look up nearby places. \(error.localizedDescription)"
        }
        switch places {
        case .missingAPIKey:
            return "CardWise was built without a place provider, so it has nowhere to get shops from."
        case .malformedResponse:
            return "The place lookup answered with something CardWise could not read."
        case .server(let status, let message):
            return "The place lookup was refused (\(status)). \(message)"
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let coordinate = GeoCoordinate(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
        guard coordinate.isValid else { return }
        userLocation = coordinate
        // Only claims the anchor the first time. After that the user owns
        // where the map is looking, and a late fix must not yank it back.
        guard center == nil else { return }
        center = coordinate
        refresh()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        log.notice("no fix: \(error.localizedDescription, privacy: .public)")
    }
}
