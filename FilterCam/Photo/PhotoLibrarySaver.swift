import AVFoundation
import CoreImage
import ImageIO
import Photos
import UniformTypeIdentifiers

struct SavedPhoto {
    let pixelWidth: Int
    let pixelHeight: Int
    let byteCount: Int
    let isLivePhoto: Bool
    /// 全分辨率原文件的临时路径，用于分享。
    let fileURL: URL?
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

/// 把照片套上滤镜后以最高质量写入相册。
/// 实况照片会把伴生视频也过一遍同样的滤镜，再和静帧配对保存。
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
                        continuation.resume(returning: try self.encodeStill(captured, transform: transform))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
        let (photoData, size) = encoded
        let shareURL = Self.writeShareFile(photoData)

        if let movieURL = captured.livePhotoMovieURL {
            return try await saveLivePhoto(
                photoData: photoData,
                size: size,
                movieURL: movieURL,
                captured: captured,
                shareURL: shareURL,
                transform: transform
            )
        }

        try await writeToLibrary { request in
            request.addResource(with: .photo, data: photoData, options: Self.photoOptions())
        }
        return SavedPhoto(
            pixelWidth: Int(size.width),
            pixelHeight: Int(size.height),
            byteCount: photoData.count,
            isLivePhoto: false,
            fileURL: shareURL
        )
    }

    /// 写一份临时 HEIC，供分享使用（全分辨率、最高质量）。
    private static func writeShareFile(_ data: Data) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("filtercam-share-\(UUID().uuidString).heic")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    // MARK: - 实况照片

    private func saveLivePhoto(
        photoData: Data,
        size: CGSize,
        movieURL: URL,
        captured: CapturedPhoto,
        shareURL: URL?,
        transform: @escaping (CIImage) -> CIImage
    ) async throws -> SavedPhoto {
        let filteredMovie = try await filterMovie(
            at: movieURL,
            identifier: Self.livePhotoIdentifier(from: captured.metadata),
            transform: transform
        )
        defer {
            try? FileManager.default.removeItem(at: movieURL)
            try? FileManager.default.removeItem(at: filteredMovie)
        }

        try await writeToLibrary { request in
            request.addResource(with: .photo, data: photoData, options: Self.photoOptions())
            let videoOptions = PHAssetResourceCreationOptions()
            videoOptions.uniformTypeIdentifier = UTType.quickTimeMovie.identifier
            request.addResource(with: .pairedVideo, fileURL: filteredMovie, options: videoOptions)
        }

        return SavedPhoto(
            pixelWidth: Int(size.width),
            pixelHeight: Int(size.height),
            byteCount: photoData.count,
            isLivePhoto: true,
            fileURL: shareURL
        )
    }

    /// 用 Core Image 逐帧套滤镜并重新导出视频，同时保留实况照片的配对标识。
    private func filterMovie(
        at url: URL,
        identifier: String?,
        transform: @escaping (CIImage) -> CIImage
    ) async throws -> URL {
        let asset = AVURLAsset(url: url)
        let composition = AVVideoComposition(asset: asset) { request in
            let source = request.sourceImage
            let output = transform(source).cropped(to: source.extent)
            request.finish(with: output, context: self.context)
        }

        guard let export = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw PhotoSaveError.saveFailed("无法创建视频导出会话")
        }
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("filtercam-live-filtered-\(UUID().uuidString).mov")
        export.outputURL = outputURL
        export.outputFileType = .mov
        export.videoComposition = composition
        export.metadata = Self.mergedMetadata(for: asset, identifier: identifier)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            export.exportAsynchronously { continuation.resume() }
        }

        guard export.status == .completed else {
            throw PhotoSaveError.saveFailed(export.error?.localizedDescription ?? "视频处理失败")
        }
        return outputURL
    }

    /// 保留原有元数据，并补上实况照片的内容标识，保证和静帧配对成功。
    private static func mergedMetadata(
        for asset: AVAsset,
        identifier: String?
    ) -> [AVMetadataItem] {
        var items = asset.metadata + asset.metadata(forFormat: .quickTimeMetadata)
        let contentKey = "com.apple.quicktime.content.identifier"

        var seen = Set<String>()
        items = items.filter { item in
            let key = (item.key as? String) ?? ""
            let signature = "\(item.keySpace?.rawValue ?? "")|\(key)|\(item.commonKey?.rawValue ?? "")"
            return seen.insert(signature).inserted
        }

        let alreadyHasIdentifier = items.contains { item in
            (item.key as? String) == contentKey
        }
        if let identifier, !alreadyHasIdentifier {
            let item = AVMutableMetadataItem()
            item.keySpace = .quickTimeMetadata
            item.key = contentKey as NSString
            item.value = identifier as NSString
            items.append(item)
        }
        return items
    }

    private static func livePhotoIdentifier(from metadata: [String: Any]) -> String? {
        guard let maker = metadata[kCGImagePropertyMakerAppleDictionary as String] as? [String: Any] else {
            return nil
        }
        return maker["17"] as? String
    }

    // MARK: - 编码

    private func encodeStill(
        _ captured: CapturedPhoto,
        transform: (CIImage) -> CIImage
    ) throws -> (Data, CGSize) {
        let oriented = captured.image.oriented(captured.orientation)
        var output = transform(oriented)

        let extent = output.extent.integral
        if extent.origin != .zero {
            output = output.transformed(
                by: CGAffineTransform(translationX: -extent.origin.x, y: -extent.origin.y)
            )
        }
        let size = output.extent.size
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

        guard let cgImage = context.createCGImage(
            output,
            from: output.extent,
            format: .RGBA8,
            colorSpace: colorSpace
        ) else {
            throw PhotoSaveError.encodingFailed
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData,
            UTType.heic.identifier as CFString,
            1,
            nil
        ) else {
            throw PhotoSaveError.encodingFailed
        }

        var properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 1.0,
            kCGImagePropertyOrientation: 1
        ]
        let exif = Self.sanitizedExif(captured.metadata)
        if !exif.isEmpty {
            properties[kCGImagePropertyExifDictionary] = exif
        }
        var tiff = (captured.metadata[kCGImagePropertyTIFFDictionary as String] as? [String: Any]) ?? [:]
        tiff[kCGImagePropertyTIFFOrientation as String] = 1
        properties[kCGImagePropertyTIFFDictionary] = tiff

        // 实况照片的静帧必须带上原始 MakerApple 信息（含配对标识）。
        if let maker = captured.metadata[kCGImagePropertyMakerAppleDictionary as String] {
            properties[kCGImagePropertyMakerAppleDictionary] = maker
        }

        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw PhotoSaveError.encodingFailed
        }
        return (data as Data, size)
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

    // MARK: - 相册

    private func writeToLibrary(
        _ build: @escaping (PHAssetCreationRequest) -> Void
    ) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.creationDate = Date()
            build(request)
        }
    }

    private static func photoOptions() -> PHAssetResourceCreationOptions {
        let options = PHAssetResourceCreationOptions()
        options.uniformTypeIdentifier = UTType.heic.identifier
        return options
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
