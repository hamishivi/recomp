import SwiftUI
import UIKit
import ImageIO
import UniformTypeIdentifiers

@MainActor
enum MealPhotoPreparation {
    static func from(data: Data) throws -> MealPhoto {
        guard data.count <= 40_000_000, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1600,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw EstimateError.imageTooLarge }
        return try from(image: UIImage(cgImage: thumbnail))
    }
    static func from(image: UIImage) throws -> MealPhoto {
        guard image.size.width > 0, image.size.height > 0 else { throw EstimateError.imageTooLarge }
        let factor = min(1, 1600 / max(image.size.width, image.size.height))
        let size = CGSize(width: max(1, floor(image.size.width * factor)), height: max(1, floor(image.size.height * factor)))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1; format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        // Re-rendering removes source EXIF/GPS/camera metadata and normalizes orientation.
        for quality in [0.82, 0.65, 0.45] {
            if let jpeg = rendered.jpegData(compressionQuality: quality), jpeg.count <= 1_500_000 {
                return MealPhoto(jpeg: jpeg)
            }
        }
        throw EstimateError.imageTooLarge
    }
}

@MainActor
struct MealCameraPicker: UIViewControllerRepresentable {
    var onPhoto: (UIImage) -> Void
    var onCancel: () -> Void
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera; picker.mediaTypes = [UTType.image.identifier]
        picker.cameraCaptureMode = .photo; picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) { }
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: MealCameraPicker
        init(parent: MealCameraPicker) { self.parent = parent }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.onCancel() }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onPhoto(image) }
            else { parent.onCancel() }
        }
    }
}
