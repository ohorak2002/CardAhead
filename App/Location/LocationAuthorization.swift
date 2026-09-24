import CoreLocation
import Observation
import UIKit

/// Owns the one permission the whole product depends on.
///
/// The app cannot do its job without **Always** access: a geofence that only
/// works while the app is open is useless, because nobody opens a rewards app
/// before paying. That is the entire reason this asks for the scarier
/// permission instead of the easy one.
///
/// iOS will not hand out Always in a single prompt. The only path Apple allows is:
///
///   not determined -> ask for When In Use  (iOS prompt 1)
///   when in use    -> ask for Always       (iOS prompt 2, "Change to Always Allow")
///   denied         -> no prompt is possible, ever again; Settings is the only route
///
/// So "take the user to Settings" is not a thing we choose to do, it is the
/// fallback iOS forces once a prompt has been answered. `requestAlwaysAccess()`
/// walks whichever part of that path applies.
@Observable
final class LocationAuthorization: NSObject, CLLocationManagerDelegate {

    private let manager = CLLocationManager()

    private(set) var status: CLAuthorizationStatus = .notDetermined

    /// Approximate Location. **Geofences do not fire with it**, so Always
    /// without Precise is not enough for reminders — iOS accepts the regions
    /// and never reports a crossing. The map still works.
    private(set) var isApproximate = false

    /// Whether the Always prompt has already been shown. iOS shows it once;
    /// after "Keep Only While Using" another request is silently ignored, so
    /// a button that asked again would do nothing at all. Stored in
    /// `UserDefaults` because the app holds more than one of these.
    private(set) var hasAskedForAlways = UserDefaults.standard.bool(forKey: LocationAuthorization.askedForAlwaysKey)
    private static let askedForAlwaysKey = "CardAhead.location.askedForAlways"

    /// Set while we are mid-escalation, so the When In Use answer can be
    /// followed straight away by the Always ask.
    private var isSeekingAlways = false

    override init() {
        super.init()
        manager.delegate = self
        status = manager.authorizationStatus
        isApproximate = manager.accuracyAuthorization == .reducedAccuracy
    }

    // MARK: - What the UI needs to know

    /// The reminders work only at this level. Anything else is a broken app.
    var hasAlways: Bool {
        status == .authorizedAlways
    }

    /// Everything reminders need: Always, and Precise.
    var remindersCanWork: Bool {
        hasAlways && !isApproximate
    }

    /// The user turned it down. Nothing we do in-app can re-ask.
    var isBlocked: Bool {
        status == .denied || status == .restricted
    }

    /// Nothing an in-app button can fix: the only route left is Settings.
    /// Denied, restricted, While Using after the Always prompt was already
    /// answered, or Approximate Location.
    var needsSettings: Bool {
        isBlocked
            || (status == .authorizedWhenInUse && hasAskedForAlways)
            || (status != .notDetermined && isApproximate)
    }

    // MARK: - Asking

    /// Moves one step along Apple's path, or opens Settings when there are no
    /// steps left. Safe to call repeatedly.
    func requestAlwaysAccess() {
        switch status {
        case .notDetermined:
            isSeekingAlways = true
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse where !hasAskedForAlways:
            isSeekingAlways = true
            askForAlways()
        case .authorizedAlways where !isApproximate:
            isSeekingAlways = false
        default:
            // Denied, restricted, Always already asked once, or Approximate
            // Location: iOS will not prompt again.
            openSettings()
        }
    }

    private func askForAlways() {
        hasAskedForAlways = true
        UserDefaults.standard.set(true, forKey: Self.askedForAlwaysKey)
        manager.requestAlwaysAuthorization()
    }

    /// Opens this app's page in Settings. iOS does not allow deep-linking to a
    /// specific switch, so the user lands on the app's own settings page and
    /// taps Location themselves.
    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString),
              UIApplication.shared.canOpenURL(url)
        else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        status = manager.authorizationStatus
        isApproximate = manager.accuracyAuthorization == .reducedAccuracy
        hasAskedForAlways = UserDefaults.standard.bool(forKey: Self.askedForAlwaysKey)

        // Prompt 1 was just answered with While Using. Go straight for Always
        // while the user still remembers agreeing to something.
        if isSeekingAlways, status == .authorizedWhenInUse, !hasAskedForAlways {
            askForAlways()
        }
        if status == .authorizedAlways || isBlocked {
            isSeekingAlways = false
        }
    }
}
