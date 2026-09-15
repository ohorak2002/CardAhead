import Foundation
import os
import UIKit
import UniformTypeIdentifiers
import UserNotifications
import CardKit

/// The coloured square on the trailing edge of a reminder.
///
/// **Why this exists at all.** A lock screen is a stack of grey rectangles
/// that all look alike, and the app icon does not help — it is the same icon
/// on every CardWise reminder, so it identifies the app and says nothing
/// about *this* arrival. Snapchat's red square is the reference: a notification
/// with one saturated block of colour in it gets looked at, and the colour
/// itself carries the first piece of meaning before a word is read.
///
/// **The mechanism is `UNNotificationAttachment`, which is the only way.**
/// There is no API for "put a coloured chip on my notification". What iOS
/// offers is an *image attachment*, which it renders as a thumbnail in exactly
/// that trailing position. So the chip is a real PNG, drawn here at scheduling
/// time. Nothing is downloaded and nothing ships in the asset catalog: the
/// colour and the symbol both already exist as data.
///
/// **iOS moves the file.** `UNNotificationAttachment` takes ownership of
/// whatever URL it is handed and relocates it into the notification store —
/// the file at that path is gone immediately afterwards. That is why every
/// call writes into its own freshly-made directory rather than reusing one
/// cached image per category: a cached file would work exactly once.
enum ReminderBadge {

    /// Rendered at 3x the ~44pt iOS draws a notification thumbnail at.
    private static let pixelSize: CGFloat = 132
    private static let log = Logger(subsystem: AppLog.subsystem, category: "reminders")

    /// A square in this category's colour with its symbol punched out in
    /// white, written to disk and wrapped for `UNMutableNotificationContent`.
    ///
    /// Returns nil rather than throwing, and the caller sends the reminder
    /// anyway: a notification with no picture on it is a smaller loss than no
    /// notification. Every failure here is a disk or an encoder failing, and
    /// neither is a reason to leave somebody standing at a till.
    static func attachment(for category: SpendingCategory) -> UNNotificationAttachment? {
        guard let data = image(for: category).pngData() else { return nil }

        // Its own directory, because iOS takes the file away and a shared
        // folder would leave the next call writing into a name that may or
        // may not still be there.
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("reminder-badges", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = folder.appendingPathComponent("badge.png")

        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return try UNNotificationAttachment(
                identifier: "badge",
                url: url,
                options: [
                    UNNotificationAttachmentOptionsTypeHintKey: UTType.png.identifier,
                    UNNotificationAttachmentOptionsThumbnailHiddenKey: false
                ]
            )
        } catch {
            // The directory is only cleaned up on the failure path. On the
            // success path there is nothing left in it to clean.
            try? FileManager.default.removeItem(at: folder)
            log.error("could not attach a badge: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// The drawing. A rounded square, the category's solid tint, a white
    /// symbol.
    ///
    /// **`pinTint`, not `tint`, and this is the trap the map already fell
    /// into.** A PNG cannot adapt to the phone's interface style — it is
    /// baked at scheduling time and shown hours later, possibly after sunset.
    /// `pinTint` is the value chosen to hold a white glyph in *both* modes
    /// (see `BrandTint.solid`), which is exactly the constraint a fixed image
    /// has. Feeding it the mode-adaptive `tint` would resolve to whichever
    /// mode the phone happened to be in when the geofence fired.
    private static func image(for category: SpendingCategory) -> UIImage {
        let side = pixelSize
        let bounds = CGRect(x: 0, y: 0, width: side, height: side)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false

        return UIGraphicsImageRenderer(bounds: bounds, format: format).image { _ in
            category.tintPalette.solid.uiColor.setFill()
            UIBezierPath(roundedRect: bounds, cornerRadius: side * 0.28).fill()

            let configuration = UIImage.SymbolConfiguration(
                pointSize: side * 0.46,
                weight: .semibold
            )
            guard let symbol = UIImage(systemName: category.symbolName, withConfiguration: configuration)?
                .withTintColor(.white, renderingMode: .alwaysOriginal)
            else { return }

            // Centred on the square's own centre rather than on the glyph's
            // bounding box origin — SF Symbols are not all the same aspect
            // ratio, and "airplane" is much wider than "cross.case.fill".
            let target = CGRect(
                x: bounds.midX - symbol.size.width / 2,
                y: bounds.midY - symbol.size.height / 2,
                width: symbol.size.width,
                height: symbol.size.height
            )
            symbol.draw(in: target)
        }
    }
}
