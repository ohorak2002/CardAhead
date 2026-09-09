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

    /// Set while we are mid-escalation, so the When In Use answer can be
    /// followed straight away by the Always ask.
    private var isSeekingAlways = false

    override init() {
        super.init()
        manager.delegate = self
        status = manager.authorizationStatus
    }

    // MARK: - What the UI needs to know

    /// The reminders work only at this level. Anything else is a broken app.
    var hasAlways: Bool {
        status == .authorizedAlways
    }

    /// True when iOS will still show a prompt. Once this is false the only way
    /// to change the answer is the Settings app.
    var canStillPrompt: Bool {
        status == .notDetermined || status == .authorizedWhenInUse
    }

    /// The user turned it down. Nothing we do in-app can re-ask.
    var isBlocked: Bool {
        status == .denied || status == .restricted
    }

    // MARK: - Asking

    /// Moves one step along Apple's path, or opens Settings when there are no
    /// steps left. Safe to call repeatedly.
    func requestAlwaysAccess() {
        switch status {
        case .notDetermined:
            isSeekingAlways = true
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            isSeekingAlways = true
            manager.requestAlwaysAuthorization()
        case .authorizedAlways:
            isSeekingAlways = false
        default:
            // Denied or restricted: iOS will not prompt again.
            openSettings()
        }
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

        // Prompt 1 was just answered with While Using. Go straight for Always
        // while the user still remembers agreeing to something.
        if isSeekingAlways, status == .authorizedWhenInUse {
            manager.requestAlwaysAuthorization()
        }
        if status == .authorizedAlways || isBlocked {
            isSeekingAlways = false
        }
    }
}
