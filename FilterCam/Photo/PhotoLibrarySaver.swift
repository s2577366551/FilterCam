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

struct SavedVideo {
    let pixelWidth: Int
    let pixelHeight: Int
    let duration: TimeInterval
    /// 成片的临时路径，用于分享。
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
        watermark: String? = nil,
        applying transform: @escaping (CIImage) -> CIImage
    ) async throws -> SavedPhoto {
        try await ensureAuthorization()

        let encoded = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<(Data, CGSize), Error>) in
            queue.async {
                autoreleasepool {
                    do {
                        continuation.resume(
                            returning: try self.encodeStill(
                                captured,
                                watermark: watermark,
                                transform: transform
                            )
                        )
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
                watermark: watermark,
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

    // MARK: - 视频

    /// 把录制好的原始视频逐帧套滤镜 + 水印，再写入相册。
    /// 导出失败时退回保存原始视频，至少不丢素材。
    func saveVideo(
        at url: URL,
        watermark: String?,
        applying transform: @escaping (CIImage) -> CIImage
    ) async throws -> SavedVideo {
        try await ensureAuthorization()

        let asset = AVURLAsset(url: url)
        let seconds = CMTimeGetSeconds(asset.duration)
        let track = asset.tracks(withMediaType: .video).first
        let natural = track?.naturalSize ?? .zero
        let duration = seconds.isFinite ? max(seconds, 0) : 0

        let filtered: URL
        do {
            filtered = try await filterMovie(
                at: url,
                identifier: nil,
                watermark: watermark,
                transform: transform
            )
        } catch {
            Log.camera.error("视频滤镜导出失败，改存原片: \(error.localizedDescription)")
            let shareURL = Self.copyForSharing(url, extension: "mov")
            try await writeToLibrary { request in
                let options = PHAssetResourceCreationOptions()
                options.uniformTypeIdentifier = UTType.quickTimeMovie.identifier
                request.addResource(with: .video, fileURL: url, options: options)
            }
            try? FileManager.default.removeItem(at: url)
            return Self.makeVideoResult(
                natural: natural,
                duration: duration,
                fileURL: shareURL
            )
        }

        // 分享副本必须在清理临时文件前复制出来。
        let shareURL = Self.copyForSharing(filtered, extension: "mov")
        defer {
            try? FileManager.default.removeItem(at: filtered)
            try? FileManager.default.removeItem(at: url)
        }

        try await writeToLibrary { request in
            let options = PHAssetResourceCreationOptions()
            options.uniformTypeIdentifier = UTType.quickTimeMovie.identifier
            request.addResource(with: .video, fileURL: filtered, options: options)
        }

        return Self.makeVideoResult(
            natural: natural,
            duration: duration,
            fileURL: shareURL
        )
    }

    /// 双摄视频：先把前后两段合成「后摄主画面 + 前摄小窗」，再套滤镜和水印。
    func saveDualVideo(
        backURL: URL,
        frontURL: URL,
        pipCenter: CGPoint = PiPLayout.defaultCenter,
        watermark: String?,
        applying transform: @escaping (CIImage) -> CIImage
    ) async throws -> SavedVideo {
        try await ensureAuthorization()

        let backAsset = AVURLAsset(url: backURL)
        let seconds = CMTimeGetSeconds(backAsset.duration)
        let duration = seconds.isFinite ? max(seconds, 0) : 0
        let natural = backAsset.tracks(withMediaType: .video).first?.naturalSize ?? .zero

        let composed = try await composePiP(
            backURL: backURL,
            frontURL: frontURL,
            pipCenter: pipCenter
        )
        defer { try? FileManager.default.removeItem(at: composed) }

        let filtered = try await filterMovie(
            at: composed,
            identifier: nil,
            watermark: watermark,
            transform: transform
        )
        let shareURL = Self.copyForSharing(filtered, extension: "mov")
        defer {
            try? FileManager.default.removeItem(at: filtered)
            try? FileManager.default.removeItem(at: backURL)
            try? FileManager.default.removeItem(at: frontURL)
        }

        try await writeToLibrary { request in
            let options = PHAssetResourceCreationOptions()
            options.uniformTypeIdentifier = UTType.quickTimeMovie.identifier
            request.addResource(with: .video, fileURL: filtered, options: options)
        }

        return SavedVideo(
            pixelWidth: Int(abs(natural.width)),
            pixelHeight: Int(abs(natural.height)),
            duration: duration,
            fileURL: shareURL
        )
    }

    /// 把轨道方向归一化到原点，Core Image 里可以直接用。
    private func orientedTransform(for track: AVAssetTrack) -> CGAffineTransform {
        let preferred = track.preferredTransform
        let rect = CGRect(origin: .zero, size: track.naturalSize).applying(preferred)
        return preferred.concatenating(
            CGAffineTransform(translationX: -rect.minX, y: -rect.minY)
        )
    }

    /// 把两段视频叠成画中画：后摄铺满，前摄是可拖动的小窗。
    private func composePiP(
        backURL: URL,
        frontURL: URL,
        pipCenter: CGPoint
    ) async throws -> URL {
        let backAsset = AVURLAsset(url: backURL)
        let frontAsset = AVURLAsset(url: frontURL)
        guard let backTrack = backAsset.tracks(withMediaType: .video).first,
              let frontTrack = frontAsset.tracks(withMediaType: .video).first else {
            throw PhotoSaveError.saveFailed("视频轨道缺失")
        }

        let composition = AVMutableComposition()
        guard let backCompositionTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ),
        let frontCompositionTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw PhotoSaveError.saveFailed("无法创建视频轨道")
        }

        let backRange = CMTimeRange(start: .zero, duration: backAsset.duration)
        try backCompositionTrack.insertTimeRange(backRange, of: backTrack, at: .zero)

        let frontDuration = CMTimeMinimum(frontAsset.duration, backAsset.duration)
        let frontRange = CMTimeRange(start: .zero, duration: frontDuration)
        try frontCompositionTrack.insertTimeRange(frontRange, of: frontTrack, at: .zero)

        if let audioTrack = backAsset.tracks(withMediaType: .audio).first,
           let audioCompositionTrack = composition.addMutableTrack(
               withMediaType: .audio,
               preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            try? audioCompositionTrack.insertTimeRange(backRange, of: audioTrack, at: .zero)
        }

        let backTransform = orientedTransform(for: backTrack)
        let frontTransform = orientedTransform(for: frontTrack)
        let oriented = CGRect(origin: .zero, size: backTrack.naturalSize)
            .applying(backTrack.preferredTransform)
        let renderSize = CGSize(width: abs(oriented.width), height: abs(oriented.height))

        let videoComposition = AVMutableVideoComposition()
        // 用 Core Image 自定义合成器，圆角、投影和 3:4 裁切和照片完全一致。
        videoComposition.customVideoCompositorClass = DualPiPCompositor.self
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.instructions = [
            DualPiPInstruction(
                timeRange: CMTimeRange(start: .zero, duration: composition.duration),
                backTrackID: backCompositionTrack.trackID,
                frontTrackID: frontCompositionTrack.trackID,
                backTransform: backTransform,
                frontTransform: frontTransform,
                pipCenter: pipCenter,
                renderSize: renderSize
            )
        ]

        guard let export = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw PhotoSaveError.saveFailed("无法创建双摄合成会话")
        }
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("filtercam-dual-composed-\(UUID().uuidString).mov")
        export.outputURL = outputURL
        export.outputFileType = .mov
        export.videoComposition = videoComposition

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            export.exportAsynchronously { continuation.resume() }
        }
        guard export.status == .completed else {
            throw PhotoSaveError.saveFailed(export.error?.localizedDescription ?? "双摄视频合成失败")
        }
        return outputURL
    }

    private static func makeVideoResult(
        natural: CGSize,
        duration: TimeInterval,
        fileURL: URL?
    ) -> SavedVideo {
        SavedVideo(
            pixelWidth: Int(abs(natural.width)),
            pixelHeight: Int(abs(natural.height)),
            duration: duration,
            fileURL: fileURL
        )
    }

    private static func copyForSharing(_ url: URL, extension ext: String) -> URL? {
        let target = FileManager.default.temporaryDirectory
            .appendingPathComponent("filtercam-share-\(UUID().uuidString).\(ext)")
        do {
            try FileManager.default.copyItem(at: url, to: target)
            return target
        } catch {
            return nil
        }
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
        watermark: String?,
        transform: @escaping (CIImage) -> CIImage
    ) async throws -> SavedPhoto {
        let filteredMovie = try await filterMovie(
            at: movieURL,
            identifier: Self.livePhotoIdentifier(from: captured.metadata),
            watermark: watermark,
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
        watermark: String? = nil,
        transform: @escaping (CIImage) -> CIImage
    ) async throws -> URL {
        let asset = AVURLAsset(url: url)

        let composition = AVVideoComposition(asset: asset) { request in
            let source = request.sourceImage
            var output = transform(source).cropped(to: source.extent)
            // 水印按实际帧尺寸生成，横竖屏都能贴准右下角。
            if let watermark,
               let layer = WatermarkRenderer.overlay(text: watermark, frame: source.extent) {
                output = layer.composited(over: output)
            }
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
        watermark: String?,
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
        if let watermark,
           let overlay = WatermarkRenderer.overlay(text: watermark, frame: output.extent) {
            output = overlay.composited(over: output)
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
