import CardKit
import PhotosUI
import SwiftUI

/// "Use a photo of your card."
///
/// This is the middle of the three card faces, and the only one that is ever
/// an exact match for the card in somebody's hand. It used to be a single row
/// buried in the hand-typed form — reachable only by people whose card was not
/// in the catalog, which is precisely the wrong audience. Somebody who picked
/// their Amex Gold from the list and wants it to *look* like their Amex Gold
/// should not have to go through a form they were deliberately spared.
///
/// The photo never leaves this iPhone. It is not uploaded, not sent to
/// analytics, not written to a log, and nothing here reads the card — see
/// `CardPhotoProcessor` for why that is a rule rather than an omission.
struct CardPhotoView: View {

    let card: Card
    /// Handed the processed image, or nil when the user removed the photo.
    var onUse: (UIImage?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(WalletStore.self) private var store

    @State private var pickedItem: PhotosPickerItem?
    @State private var captured: UIImage?
    @State private var isShowingCamera = false
    @State private var didFindOutline = true

    /// The photo already on the card, if there is one. Shown until a new one
    /// is taken so the screen opens on what it is about to change.
    private var existing: Image? { store.photo(for: card) }

    var body: some View {
        NavigationStack {
            List {
                previewSection
                actionsSection
                if captured != nil || card.photoFilename != nil { removeSection }
                privacySection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Your card photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Use this") {
                        onUse(captured)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(captured == nil)
                }
            }
            .fullScreenCover(isPresented: $isShowingCamera) {
                CameraPicker(
                    onCapture: { accept($0) },
                    onFinish: { isShowingCamera = false }
                )
                .ignoresSafeArea()
            }
            .onChange(of: pickedItem) { _, item in
                Task { await loadFromLibrary(item) }
            }
        }
    }

    // MARK: - What it will look like

    private var previewSection: some View {
        Section {
            VStack(alignment: .leading, spacing: Metric.snug) {
                // Drawn through the same view the wallet uses, so what is on
                // screen here is exactly what lands in the stack — including
                // the shadow, the corner radius and the vibrancy gradient
                // under the text.
                CardFaceView(card: card, photo: previewImage)

                if captured != nil && !didFindOutline {
                    Label(
                        "Could not find the card's edges, so this is the middle of your photo. Retake it flat on, filling the frame, and it will straighten itself.",
                        systemImage: "viewfinder"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
            .listRowInsets(EdgeInsets(top: 8, leading: Metric.margin, bottom: 8, trailing: Metric.margin))
            .listRowBackground(Color.clear)
        }
    }

    /// The new photo if one has been taken, otherwise the one already saved.
    private var previewImage: Image? {
        if let captured { return Image(uiImage: captured) }
        return existing
    }

    // MARK: - Getting one

    private var actionsSection: some View {
        Section {
            // Absent in the simulator, which has no camera — a button that
            // opens nothing is worse than no button.
            if CameraPicker.isAvailable {
                Button {
                    isShowingCamera = true
                } label: {
                    Label(captured == nil ? "Take a photo" : "Take another", systemImage: "camera")
                }
            }
            PhotosPicker(selection: $pickedItem, matching: .images) {
                Label("Choose from your photos", systemImage: "photo.on.rectangle")
            }
        } header: {
            Text("Photograph the front").textCase(nil)
        } footer: {
            Text("Lay the card flat, fill the frame, and CardAhead will straighten it and crop it to card shape. Photograph the front — the back is the side with the security code on it, and nothing here needs it.")
        }
    }

    private var removeSection: some View {
        Section {
            Button("Use the drawn card instead", role: .destructive) {
                onUse(nil)
                dismiss()
            }
        } footer: {
            Text("Deletes the photo from this iPhone and goes back to the card CardAhead draws.")
        }
    }

    private var privacySection: some View {
        Section {
            Label("Stays on this iPhone. Never uploaded, never sent anywhere.", systemImage: "iphone")
            Label("CardAhead does not read your card. No number, no security code, no expiry date — the app has never needed them.", systemImage: "eye.slash")
        } footer: {
            Text("Erasing everything in Settings deletes your card photos with the rest.")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    // MARK: - Processing

    /// Synchronous on purpose — see `CardPhotoProcessor.workingWidth`. The
    /// photo is shrunk to the size the app actually draws before anything
    /// looks at it, which makes the whole pipeline quick enough not to be
    /// worth the cost of getting a non-`Sendable` `UIImage` safely across an
    /// actor boundary and back.
    private func accept(_ image: UIImage) {
        let result = CardPhotoProcessor.process(image)
        captured = result.image
        didFindOutline = result.foundOutline
    }

    private func loadFromLibrary(_ item: PhotosPickerItem?) async {
        guard let item,
              let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data)
        else { return }
        accept(image)
    }
}

#Preview {
    CardPhotoView(card: CardCatalog.amexGold, onUse: { _ in })
        .environment(WalletStore.previewStore())
}
