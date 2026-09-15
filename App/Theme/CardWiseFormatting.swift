import Foundation
import CardKit

/// Money, formatted once.
///
/// This was a `private func money(_:)` copied verbatim into two views, which
/// is the shape a formatting bug takes before anybody notices: two identical
/// copies drift the day one screen needs cents and the other does not, and
/// then the same card costs "$375" on one screen and "$375.00" on the next.
///
/// **Whole dollars on purpose.** Every annual fee and credit this app states
/// is a round number in the issuer's own marketing, and showing "$375.00"
/// implies a precision the figure does not have.
///
/// **Never assert an exact currency string in a test.** `NumberFormatter`
/// honours `maximumFractionDigits` on Darwin and ignores it on Linux, and
/// CardKit's suite runs on both — a test that pins "$375" passes on the macOS
/// job and fails on the Linux one. Assert the digits, not the formatting.
enum CardWiseFormat {

    static func money(_ amount: Money) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "$\(amount)"
    }
}
