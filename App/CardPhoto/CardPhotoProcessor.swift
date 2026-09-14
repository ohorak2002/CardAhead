import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit
import Vision

/// Turns a snapshot of a card held at arm's length into something that looks
/// like a card face.
///
/// Three steps, each of which is allowed to fail without taking the photo with
/// it: find the card's four corners, flatten the perspective onto them, crop to
/// the real card proportion. A photo taken at an angle on a kitchen table comes
/// out looking like the thing in the wallet; a photo of nothing in particular
/// comes out centre-cropped, which is what it would have been anyway.
///
/// **What this deliberately does not do is read the card.** The only Vision
/// request here is `VNDetectRectanglesRequest`, which finds quadrilaterals and
/// nothing else — no text recognition, no OCR, no classifier. There is no code
/// path in this app that extracts a card number, a security code or an expiry
/// date, and there must not be one: the app never needs them, and a card photo
/// is the single most sensitive thing a user of this app will ever hand it.
/// See `docs/card-art.md`.
///
/// Everything runs on this device. Nothing here touches the network, and the
/// image is never handed to logging, analytics or a crash reporter.
enum CardPhotoProcessor {

    /// ISO/IEC 7810 ID-1 — 85.60 × 53.98 mm. The same number `CardFaceView`
    /// draws at, so a photo and a drawing are the same shape in the stack.
    static let cardAspectRatio: CGFloat = 1.586

    /// What the pipeline works at.
    ///
    /// This is the reason none of this needs a background thread. A phone
    /// camera hands over twelve megapixels; `WalletStore.storePhoto` throws all
    /// but 640 points of width away again, and nothing in the app ever draws a
    /// card face larger than a phone screen. Detecting a rectangle in twelve
    /// megapixels and then re-projecting it would take long enough to need
    /// moving off the main thread — and every pixel of that work would be
    /// discarded moments later. Shrinking first makes it fast enough to be
    /// invisible, which is cheaper than making it concurrent and correct.
    private static let workingWidth: CGFloat = 1600

    struct Result {
        var image: UIImage
        /// False when the card's outline was not found, so this is a plain
        /// centre crop of whatever was photographed. The UI says so rather
        /// than pretending — but it still offers the picture, because a
        /// detector that failed must never stop somebody adding their card.
        var foundOutline: Bool
    }

    /// The whole pipeline. Never throws, never returns nil, and runs detection
    /// exactly once: the worst case is the photo the user took, cropped to
    /// card shape.
    static func process(_ image: UIImage) -> Result {
        let working = downscaled(uprighted(image), toWidth: workingWidth)
        if let flattened = perspectiveCorrected(working) {
            return Result(image: croppedToCardShape(flattened), foundOutline: true)
        }
        return Result(image: croppedToCardShape(working), foundOutline: false)
    }

    /// Shrinks to the working width, and never enlarges — a photo already
    /// smaller than this is left exactly as it is.
    private static func downscaled(_ image: UIImage, toWidth width: CGFloat) -> UIImage {
        guard let cgImage = image.cgImage, CGFloat(cgImage.width) > width else { return image }
        let scale = width / CGFloat(cgImage.width)
        let size = CGSize(
            width: width.rounded(.down),
            height: (CGFloat(cgImage.height) * scale).rounded(.down)
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            UIImage(cgImage: cgImage).draw(in: CGRect(origin: .zero, size: size))
        }
    }

    // MARK: - Orientation

    /// Redraws the image so its pixels are the right way up.
    ///
    /// A photo from the camera usually carries its rotation as metadata rather
    /// than in the pixels. Vision and Core Image both work on the pixels, so
    /// skipping this step finds the card sideways, or not at all.
    private static func uprighted(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    // MARK: - Finding the card

    private static func detectCard(in image: UIImage) -> VNRectangleObservation? {
        guard let cgImage = image.cgImage else { return nil }

        let request = VNDetectRectanglesRequest()
        // A card is 1.586:1, so its short side over its long side is 0.63.
        // The window either side of that is the perspective budget: a card
        // photographed at a slight angle measures narrower than it is.
        request.minimumAspectRatio = 0.45
        request.maximumAspectRatio = 0.85
        request.minimumSize = 0.2
        request.minimumConfidence = 0.6
        request.maximumObservations = 1
        // The card's own rounded corners, and the table edge behind it, both
        // read as slightly-not-square. A little slack here is the difference
        // between finding the card and finding nothing.
        request.quadratureTolerance = 25

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            // A detector that fell over is a detector that found nothing.
            // The caller's fallback is a perfectly good photograph.
            return nil
        }
        return request.results?.first
    }

    // MARK: - Flattening

    private static func perspectiveCorrected(_ image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage,
              let card = detectCard(in: image)
        else { return nil }

        let source = CIImage(cgImage: cgImage)
        let extent = source.extent

        // Vision reports corners in a 0–1 space with its origin at the bottom
        // left, which is the same corner Core Image uses. No flip needed —
        // and this is exactly the kind of thing that looks fine until every
        // photo comes out upside down.
        func absolute(_ point: CGPoint) -> CGPoint {
            CGPoint(x: extent.origin.x + point.x * extent.width,
                    y: extent.origin.y + point.y * extent.height)
        }

        let filter = CIFilter.perspectiveCorrection()
        filter.inputImage = source
        filter.topLeft = absolute(card.topLeft)
        filter.topRight = absolute(card.topRight)
        filter.bottomLeft = absolute(card.bottomLeft)
        filter.bottomRight = absolute(card.bottomRight)

        guard let output = filter.outputImage else { return nil }
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let rendered = context.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: rendered)
    }

    // MARK: - Cropping

    /// Centre-crops to the card proportion, in pixels rather than points so the
    /// result does not depend on the screen it was captured on.
    static func croppedToCardShape(_ image: UIImage) -> UIImage {
        guard let cgImage = uprighted(image).cgImage else { return image }
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        guard width > 0, height > 0 else { return image }

        var rect = CGRect(x: 0, y: 0, width: width, height: height)
        let ratio = width / height
        if ratio > cardAspectRatio {
            rect.size.width = (height * cardAspectRatio).rounded(.down)
            rect.origin.x = ((width - rect.size.width) / 2).rounded(.down)
        } else if ratio < cardAspectRatio {
            rect.size.height = (width / cardAspectRatio).rounded(.down)
            rect.origin.y = ((height - rect.size.height) / 2).rounded(.down)
        }

        guard let cropped = cgImage.cropping(to: rect) else { return image }
        return UIImage(cgImage: cropped)
    }
}
