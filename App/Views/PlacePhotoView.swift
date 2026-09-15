import SwiftUI
import CardKit

/// A photograph of a real business, or something worth looking at instead.
///
/// **The whole point of this view is the "instead".** A photo view that is
/// beautiful when the image arrives and a grey box when it does not is a view
/// that looks broken most of the time — most shops on a suburban high street
/// have no photograph, the app runs with no Places key at all in any build
/// that is not Oren's, and the first second of every image is a wait. So there
/// are four states and each one is drawn deliberately:
///
/// - **The photograph**, cropped to fill, fading in.
/// - **Waiting for it**, a quiet pulse in the place's own colour — not a
///   spinner, which asks to be watched.
/// - **No photograph for this place**, the category glyph on a soft wash of
///   its colour. The same colour as its pin, which is the recognition job the
///   picture was doing, done the only other way available.
/// - **No photographs at all**, because this build has no key: identical to
///   the above, and deliberately so. "CardWise cannot show you pictures" is
///   not information anybody can act on.
///
/// The fallback is not an apology. It is what CI photographs — the screenshot
/// run is seeded and never calls Google — so it is the state that gets looked
/// at hardest.
struct PlacePhotoView: View {

    var photo: PlacePhoto?
    /// Drawn when there is no photograph. Comes from the place's category, so
    /// it matches the pin and the row.
    var symbolName: String
    var tint: Color
    var use: PlacePhotoUse
    var cornerRadius: CGFloat = Metric.tileRadius

    @Environment(\.placePhotos) private var loader
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var image: UIImage?
    @State private var isLoading = false

    var body: some View {
        // **`Color.clear` as the base, not the image itself.** A resizable
        // image sized by its own content proposes its intrinsic size upward
        // and fights whatever frame the caller set — the same class of trap
        // that once drew every wallet card at a third of its width. A clear
        // rectangle takes exactly the space offered, and the image is laid
        // over it and clipped.
        Color.clear
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                } else {
                    fallback
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            // Keyed on the photo *and* the size, so a row scrolling into a
            // different place reloads and a hero does not inherit the row's
            // thumbnail. Re-running on every redraw is what this avoids.
            .task(id: taskID) { await load() }
            .accessibilityHidden(true)
    }

    private var taskID: String {
        (photo?.name ?? "none") + "-" + use.rawValue
    }

    // MARK: - When there is no photograph

    private var fallback: some View {
        ZStack {
            // Two stops of the same colour rather than a flat fill: a flat
            // wash beside a photograph reads as a failed image, a gradient
            // reads as a drawn tile.
            LinearGradient(
                colors: [tint.opacity(0.22), tint.opacity(0.10)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: symbolName)
                .font(.system(size: glyphSize, weight: .semibold))
                .foregroundStyle(tint.opacity(isLoading ? 0.35 : 0.55))
        }
        // The wait is a slow breath on the glyph, not a shimmer sweeping
        // across the tile: twenty rows of sweeping highlights is a disco.
        // Under Reduce Motion it simply sits at the dimmer value.
        .animation(
            isLoading && !reduceMotion
                ? .easeInOut(duration: 1.1).repeatForever(autoreverses: true)
                : .default,
            value: isLoading
        )
    }

    /// Proportional to the bucket rather than measured, so a row thumbnail
    /// and a hero do not end up with the same 28-point fork on them.
    private var glyphSize: CGFloat {
        switch use {
        case .row: return 24
        case .card: return 40
        case .hero: return 52
        }
    }

    // MARK: - Loading

    private func load() async {
        guard let photo else {
            image = nil
            isLoading = false
            return
        }
        // Not reset to nil first: on a re-render with the same photo that
        // would blink the image out and back. The task id already guarantees
        // this only runs when the photo actually changed.
        isLoading = true
        let loaded = await loader.image(for: photo, use: use)
        guard !Task.isCancelled else { return }

        if reduceMotion {
            image = loaded
        } else {
            withAnimation(.easeOut(duration: 0.22)) { image = loaded }
        }
        isLoading = false
    }
}

extension PlacePhotoView {
    /// The common case: a photograph of a place, falling back to that place's
    /// own category colour and symbol.
    init(place: MapPlace, use: PlacePhotoUse, cornerRadius: CGFloat = Metric.tileRadius) {
        self.init(
            photo: place.photo,
            symbolName: place.mapCategory.symbolName,
            tint: place.mapCategory.listTint,
            use: use,
            cornerRadius: cornerRadius
        )
    }
}

/// The credit under a photograph.
///
/// Google's terms require showing the attributions supplied with an image
/// wherever it is displayed, and this is where that obligation is met: the
/// place detail, which is the one screen with room to read one. Drawn small
/// and quiet — it is a legal requirement rather than something anybody came
/// for — but drawn, and never in a colour that needs good light to see.
struct PlacePhotoCredit: View {
    let photo: PlacePhoto?

    var body: some View {
        if let text = photo?.attributionText {
            Text(text)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}
