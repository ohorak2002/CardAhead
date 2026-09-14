import SwiftUI
import UIKit

/// The system camera, for photographing a card.
///
/// `UIImagePickerController` rather than a hand-built `AVCaptureSession`, on
/// purpose. A custom capture screen is several hundred lines of session,
/// preview layer, orientation and lifecycle handling, all of which has to be
/// right on a device nobody here can test on — and it would buy one thing: a
/// card-shaped guide rectangle on the viewfinder. `CardPhotoProcessor` finds
/// the card afterwards instead, which works whatever the photo came from.
///
/// Permission is requested by the system the first time this is presented, and
/// only then — which is why there is no camera call anywhere near launch. The
/// string iOS shows is `NSCameraUsageDescription` in `project.yml`.
struct CameraPicker: UIViewControllerRepresentable {

    /// Handed the photo exactly as taken. Processing happens upstream, so a
    /// failure to find the card cannot lose the picture.
    var onCapture: (UIImage) -> Void
    /// Called on cancel *and* after a capture, so the presenter owns dismissal
    /// rather than this view reaching for an environment value that resolves
    /// at a different moment than the coordinator is built.
    var onFinish: () -> Void

    /// False in the simulator, which is where CI photographs this app — so the
    /// button has to be hidden rather than presented and left dead.
    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.allowsEditing = false
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, onFinish: onFinish)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let onCapture: (UIImage) -> Void
        private let onFinish: () -> Void

        init(onCapture: @escaping (UIImage) -> Void, onFinish: @escaping () -> Void) {
            self.onCapture = onCapture
            self.onFinish = onFinish
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onCapture(image)
            }
            onFinish()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish()
        }
    }
}
