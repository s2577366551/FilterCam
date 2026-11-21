import CoreImage
import UIKit

final class ThumbnailService {
    private let pipeline: FilterPipeline
    private let context: CIContext
    private let queue = DispatchQueue(label: "com.filtercam.thumbnails", qos: .utility)

    init(pipeline: FilterPipeline, context: CIContext) {
        self.pipeline = pipeline
        self.context = context
    }

    func generate(
        from frame: CIImage,
        presets: [FilterPreset],
        size: CGFloat = 120,
        completion: @escaping ([String: UIImage]) -> Void
    ) {
        queue.async {
            let square = Self.centerSquare(frame, size: size)
            var result: [String: UIImage] = [:]
            for preset in presets {
                let processed = self.pipeline.process(square, preset: preset, intensity: 1)
                guard let cgImage = self.context.createCGImage(processed, from: square.extent) else {
                    continue
                }
                result[preset.id] = UIImage(cgImage: cgImage)
            }
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    static func centerSquare(_ image: CIImage, size: CGFloat) -> CIImage {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0, size > 0 else { return image }

        let scale = max(size / extent.width, size / extent.height)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let side = size / scale
        let crop = CGRect(
            x: scaled.extent.midX - side / 2,
            y: scaled.extent.midY - side / 2,
            width: side,
            height: side
        )
        let cropped = scaled.cropped(to: crop)
        let normalize = CGAffineTransform(translationX: -crop.minX, y: -crop.minY)
            .concatenating(CGAffineTransform(scaleX: size / side, y: size / side))
        return cropped.transformed(by: normalize)
    }
}
