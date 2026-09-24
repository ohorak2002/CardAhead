import Foundation

/// The window in which CardAhead says nothing.
///
/// **A reminder is only ever useful at a till, and nobody is at a till at two
/// in the morning.** A geofence can still fire then — a hotel at midnight, a
/// petrol station on a long drive — and the notification would be technically
/// correct and socially unforgivable.
///
/// **This must never be worked around with an interruption level.** iOS gives
/// the *user* a Focus mode and a sleep schedule; Time Sensitive is the flag
/// that punches through them, and using it to deliver a restaurant tip at 11pm
/// is the behaviour that gets an app's notifications switched off for good.
/// Quiet hours suppress; they do not downgrade.
public struct QuietHours: Codable, Hashable, Sendable {

    public var isEnabled: Bool
    /// Minutes past midnight, local time. Stored as minutes rather than a
    /// `Date` because this is a time of day and not a moment — a `Date` would
    /// carry a day with it and go stale tomorrow.
    public var startMinutes: Int
    public var endMinutes: Int

    public init(isEnabled: Bool = true, startMinutes: Int = 22 * 60, endMinutes: Int = 8 * 60) {
        self.isEnabled = isEnabled
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
    }

    public init(isEnabled: Bool = true, startHour: Int, endHour: Int) {
        self.init(isEnabled: isEnabled, startMinutes: startHour * 60, endMinutes: endHour * 60)
    }

    /// 10pm to 8am.
    public static let standard = QuietHours()

    /// **The wrap-around is the whole of this method.** A quiet window that
    /// runs 22:00 → 08:00 crosses midnight, so the naive `start <= now < end`
    /// is false for every minute of it. Written once here, with a test per
    /// edge, rather than at the call site where it would be written wrong.
    ///
    /// A window whose ends are equal is treated as *no* quiet hours rather
    /// than as twenty-four of them: somebody who dragged both sliders to the
    /// same place meant "off", not "never notify me again".
    public func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard isEnabled, startMinutes != endMinutes else { return false }
        let now = Self.minutesOfDay(date, calendar: calendar)
        if startMinutes < endMinutes {
            return now >= startMinutes && now < endMinutes
        }
        // Crosses midnight: quiet from the start until midnight, and from
        // midnight until the end.
        return now >= startMinutes || now < endMinutes
    }

    /// When the quiet window this date falls in will end, so a suppression can
    /// say "next eligible at 8:00 AM" rather than only "not now".
    public func end(after date: Date, calendar: Calendar = .current) -> Date? {
        guard contains(date, calendar: calendar) else { return nil }
        let now = Self.minutesOfDay(date, calendar: calendar)
        let startOfDay = calendar.startOfDay(for: date)
        // Past the end already means the window started tonight and ends
        // tomorrow morning.
        let minutesUntil = now < endMinutes
            ? endMinutes - now
            : (24 * 60 - now) + endMinutes
        return calendar.date(byAdding: .minute, value: minutesUntil, to: date)
            ?? startOfDay.addingTimeInterval(Double(minutesUntil) * 60)
    }

    static func minutesOfDay(_ date: Date, calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// "10:00 PM to 8:00 AM", for the settings row.
    public func describe(calendar: Calendar = .current, locale: Locale = .current) -> String {
        "\(Self.label(startMinutes, locale: locale)) to \(Self.label(endMinutes, locale: locale))"
    }

    private static func label(_ minutes: Int, locale: Locale) -> String {
        var components = DateComponents()
        components.hour = minutes / 60
        components.minute = minutes % 60
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        guard let date = calendar.date(from: components) else { return "\(minutes / 60):00" }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
}
