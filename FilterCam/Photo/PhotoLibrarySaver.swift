import CoreImage
import ImageIO
import Photos
import UniformTypeIdentifiers

struct SavedPhoto {
    let pixelWidth: Int
    let pixelHeight: Int
    let byteCount: Int
}

enum PhotoSaveError: LocalizedError {
    case notAuthorized
    case encodingFailed
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "没有相册写入权限，请到设置里允许"
        case .encodingFailed:
            return "照片编码失败"
        case .saveFailed(let message):
            return "保存失败：\(message)"
        }
    }
}

/// 把全分辨率照片套上滤镜后，以最高质量（HEIC，质量 1.0）写入相册。
/// 整个过程在后台队列执行，不阻塞预览。
final class PhotoLibrarySaver {
    private let queue = DispatchQueue(label: "com.filtercam.photo.save", qos: .userInitiated)
    private let context: CIContext

    init(context: CIContext) {
        self.context = context
    }

    func save(
        _ captured: CapturedPhoto,
        applying transform: @escaping (CIImage) -> CIImage
    ) async throws -> SavedPhoto {
        try await ensureAuthorization()

        let encoded = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<(Data, CGSize), Error>) in
            queue.async {
                autoreleasepool {
                    do {
                        let result = try self.encode(captured, transform: transform)
                        continuation.resume(returning: result)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }

        let (data, size) = encoded
        let identifier = UTType.heic.identifier
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            let options = PHAssetResourceCreationOptions()
            options.uniformTypeIdentifier = identifier
            request.addResource(with: .photo, data: data, options: options)
            request.creationDate = Date()
        }

        return SavedPhoto(
            pixelWidth: Int(size.width),
            pixelHeight: Int(size.height),
            byteCount: data.count
        )
    }

    // MARK: - 编码

    private func encode(
        _ captured: CapturedPhoto,
        transform: (CIImage) -> CIImage
    ) throws -> (Data, CGSize) {
        let oriented = captured.image.oriented(captured.orientation)
        var output = transform(oriented)

        // 保证从 (0,0) 开始，避免 HEIF 写出时被裁掉。
        let extent = output.extent.integral
        if extent.origin != .zero {
            output = output.transformed(
                by: CGAffineTransform(translationX: -extent.origin.x, y: -extent.origin.y)
            )
        }
        let size = output.extent.size

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        var options: [CIImageRepresentationOption: Any] = [
            CIImageRepresentationOption(
                rawValue: kCGImageDestinationLossyCompressionQuality as String
            ): 1.0
        ]

        let exif = Self.sanitizedExif(captured.metadata)
        if !exif.isEmpty {
            options[CIImageRepresentationOption(rawValue: kCGImagePropertyExifDictionary as String)] = exif
        }
        var tiff = (captured.metadata[kCGImagePropertyTIFFDictionary as String] as? [String: Any]) ?? [:]
        tiff[kCGImagePropertyTIFFOrientation as String] = 1
        options[CIImageRepresentationOption(rawValue: kCGImagePropertyTIFFDictionary as String)] = tiff
        options[CIImageRepresentationOption(rawValue: kCGImagePropertyOrientation as String)] = 1

        if let data = context.heifRepresentation(
            of: output,
            format: .RGBA8,
            colorSpace: colorSpace,
            options: options
        ) {
            return (data, size)
        }
        // HEIF 不可用时退回 JPEG，仍然按最高质量写。
        if let data = context.jpegRepresentation(
            of: output,
            colorSpace: colorSpace,
            options: options
        ) {
            return (data, size)
        }
        throw PhotoSaveError.encodingFailed
    }

    /// 去掉与原图尺寸冲突的 EXIF 字段，避免相册显示错误尺寸。
    private static func sanitizedExif(_ metadata: [String: Any]) -> [String: Any] {
        guard let exif = metadata[kCGImagePropertyExifDictionary as String] as? [String: Any] else {
            return [:]
        }
        var clean = exif
        clean.removeValue(forKey: kCGImagePropertyExifPixelXDimension as String)
        clean.removeValue(forKey: kCGImagePropertyExifPixelYDimension as String)
        return clean
    }

    // MARK: - 权限

    private func ensureAuthorization() async throws {
        switch PHPhotoLibrary.authorizationStatus(for: .addOnly) {
        case .authorized, .limited:
            return
        case .notDetermined:
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else {
                throw PhotoSaveError.notAuthorized
            }
        default:
            throw PhotoSaveError.notAuthorized
        }
    }
}
