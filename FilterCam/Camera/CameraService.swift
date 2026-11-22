import AVFoundation
import CoreImage
import CoreMedia
import ImageIO

final class CameraService: NSObject, CameraServicing {
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.filtercam.camera.session")
    private let videoQueue = DispatchQueue(label: "com.filtercam.camera.video", qos: .userInitiated)
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()

    private var videoInput: AVCaptureDeviceInput?
    private var position: AVCaptureDevice.Position = .back
    private var flashMode: FlashMode = .auto
    private var photoResolution: PhotoResolution = .standard
    private var isConfigured = false
    private var isObserving = false
    private let photoLock = NSLock()
    private var photoContinuation: CheckedContinuation<CapturedPhoto, Error>?

    var onFrame: ((CIImage) -> Void)?
    var onStateChange: ((CameraRuntimeState) -> Void)?

    func start() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async {
                do {
                    try self.configureIfNeeded()
                    self.observeSessionIfNeeded()
                    if !self.session.isRunning {
                        self.session.startRunning()
                    }
                    self.onStateChange?(.running)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stop() {
        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
            self.onStateChange?(.idle)
        }
    }

    func switchCamera() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async {
                do {
                    try self.switchCameraLocked()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func setFlashMode(_ mode: FlashMode) {
        sessionQueue.async { self.flashMode = mode }
    }

    func setPhotoResolution(_ resolution: PhotoResolution) {
        sessionQueue.async { self.photoResolution = resolution }
    }

    func capturePhoto() async throws -> CapturedPhoto {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async {
                guard self.session.isRunning else {
                    continuation.resume(throwing: CameraError.captureFailed("相机会话未运行"))
                    return
                }
                self.photoLock.lock()
                let isBusy = self.photoContinuation != nil
                if !isBusy {
                    self.photoContinuation = continuation
                }
                self.photoLock.unlock()
                guard !isBusy else {
                    continuation.resume(throwing: CameraError.captureFailed("上一张照片仍在处理中"))
                    return
                }

                let settings = self.makePhotoSettings()
                self.photoOutput.capturePhoto(with: settings, delegate: self)
            }
        }
    }

    /// 按当前设备能力生成全分辨率、最高质量的拍照参数。
    private func makePhotoSettings() -> AVCapturePhotoSettings {
        let settings: AVCapturePhotoSettings
        if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
            settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
        } else {
            settings = AVCapturePhotoSettings()
        }

        settings.maxPhotoDimensions = photoDimensions(for: photoResolution)
        settings.photoQualityPrioritization = .quality
        if photoOutput.supportedFlashModes.contains(flashMode.avMode) {
            settings.flashMode = flashMode.avMode
        }
        return settings
    }

    /// 按档位从设备支持的尺寸里挑一个：
    /// - 标准：不超过 1200 万像素的最大档（通常就是 4032×3024）
    /// - 高清：传感器最大尺寸（iPhone 15 Pro 上是 8064×6048）
    private func photoDimensions(for resolution: PhotoResolution) -> CMVideoDimensions {
        let allowed = photoOutput.maxPhotoDimensions
        guard let device = videoInput?.device else { return allowed }
        let supported = device.activeFormat.supportedMaxPhotoDimensions
            .sorted { Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height) }
        guard let smallest = supported.first, let largest = supported.last else {
            return allowed
        }
        switch resolution {
        case .high:
            return largest
        case .standard:
            let limit = 12_000_000
            return supported.last { Int($0.width) * Int($0.height) <= limit } ?? smallest
        }
    }

    // MARK: - 对焦

    func focus(at devicePoint: CGPoint) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async {
                do {
                    try self.applyFocus(at: devicePoint)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func setManualFocus(_ lensPosition: Float) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async {
                do {
                    try self.applyManualFocus(lensPosition)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func resumeAutoFocus() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async {
                do {
                    try self.applyContinuousFocus()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func applyFocus(at point: CGPoint) throws {
        guard let device = videoInput?.device else {
            throw CameraError.configurationFailed("相机未就绪")
        }
        let clamped = CGPoint(
            x: min(max(point.x, 0), 1),
            y: min(max(point.y, 0), 1)
        )
        do {
            try device.lockForConfiguration()
        } catch {
            throw CameraError.captureFailed("无法锁定相机配置")
        }
        defer { device.unlockForConfiguration() }

        if device.isFocusPointOfInterestSupported {
            device.focusPointOfInterest = clamped
            if device.isFocusModeSupported(.autoFocus) {
                device.focusMode = .autoFocus
            }
        }
        if device.isExposurePointOfInterestSupported {
            device.exposurePointOfInterest = clamped
            if device.isExposureModeSupported(.autoExpose) {
                device.exposureMode = .autoExpose
            }
        }
    }

    private func applyManualFocus(_ lensPosition: Float) throws {
        guard let device = videoInput?.device else {
            throw CameraError.configurationFailed("相机未就绪")
        }
        guard device.isFocusModeSupported(.locked) else {
            throw CameraError.captureFailed("当前摄像头不支持手动对焦")
        }
        do {
            try device.lockForConfiguration()
        } catch {
            throw CameraError.captureFailed("无法锁定相机配置")
        }
        defer { device.unlockForConfiguration() }

        device.setFocusModeLocked(lensPosition: min(max(lensPosition, 0), 1))
        if device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
        }
    }

    private func applyContinuousFocus() throws {
        guard let device = videoInput?.device else {
            throw CameraError.configurationFailed("相机未就绪")
        }
        do {
            try device.lockForConfiguration()
        } catch {
            throw CameraError.captureFailed("无法锁定相机配置")
        }
        defer { device.unlockForConfiguration() }

        if device.isFocusModeSupported(.continuousAutoFocus) {
            device.focusMode = .continuousAutoFocus
        }
        if device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
        }
    }

    private func configureIfNeeded() throws {
        guard !isConfigured else { return }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        // 用 .inputPriority 手动挑格式：要求视频尺寸不超过 12MP（保证预览帧不过大），
        // 同时在该约束下取「支持的最大拍照尺寸」最大的格式。
        // iPhone 15 Pro 上这样可以拿到 8064×6048（4800 万）的静态拍照能力，
        // 而预览仍然走 4032×3024 的视频流。
        session.sessionPreset = .inputPriority

        guard let device = Self.device(position: position) else {
            throw CameraError.noCameraAvailable
        }
        if let format = Self.bestPhotoFormat(for: device) {
            Self.applyFormat(format, to: device)
        } else {
            session.sessionPreset = .photo
        }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw CameraError.configurationFailed("无法添加相机输入")
        }
        session.addInput(input)
        videoInput = input

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        guard session.canAddOutput(videoOutput) else {
            throw CameraError.configurationFailed("无法添加视频输出")
        }
        session.addOutput(videoOutput)

        guard session.canAddOutput(photoOutput) else {
            throw CameraError.configurationFailed("无法添加照片输出")
        }
        session.addOutput(photoOutput)
        photoOutput.maxPhotoQualityPrioritization = .quality
        Self.applyMaxPhotoDimensions(to: photoOutput, device: device)

        applyConnectionSettings(position: position)
        isConfigured = true
    }

    private func switchCameraLocked() throws {
        let newPosition: AVCaptureDevice.Position = position == .back ? .front : .back
        guard let device = Self.device(position: newPosition) else {
            throw CameraError.noCameraAvailable
        }
        let input = try AVCaptureDeviceInput(device: device)

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        let previousInput = videoInput
        if let previousInput {
            session.removeInput(previousInput)
        }
        guard session.canAddInput(input) else {
            if let previousInput {
                session.addInput(previousInput)
            }
            throw CameraError.configurationFailed("无法切换摄像头")
        }
        session.addInput(input)
        videoInput = input
        position = newPosition
        if let format = Self.bestPhotoFormat(for: device) {
            Self.applyFormat(format, to: device)
        }
        Self.applyMaxPhotoDimensions(to: photoOutput, device: device)
        // 换摄像头后回到连续自动对焦，避免沿用上一颗镜头的锁定状态。
        if (try? device.lockForConfiguration()) != nil {
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            device.unlockForConfiguration()
        }
        applyConnectionSettings(position: newPosition)
    }

    // MARK: - 格式选择

    /// 在视频尺寸不超过 12MP 的格式里，挑拍照尺寸最大的那个。
    private static func bestPhotoFormat(for device: AVCaptureDevice) -> AVCaptureDevice.Format? {
        let candidates = device.formats.filter { format in
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            guard dims.width > 0, dims.height > 0 else { return false }
            guard dims.width <= 4032, dims.height <= 3024 else { return false }
            let ranges = format.videoSupportedFrameRateRanges
            guard let maxRate = ranges.map(\.maxFrameRate).max() else { return false }
            return maxRate >= 24
        }
        return candidates.max { lhs, rhs in
            photoArea(lhs) < photoArea(rhs)
        }
    }

    private static func photoArea(_ format: AVCaptureDevice.Format) -> Int {
        format.supportedMaxPhotoDimensions.reduce(0) { partial, dims in
            max(partial, Int(dims.width) * Int(dims.height))
        }
    }

    private static func applyFormat(_ format: AVCaptureDevice.Format, to device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            device.activeFormat = format
            let target: Double = 30
            if format.videoSupportedFrameRateRanges.contains(where: {
                $0.minFrameRate <= target && $0.maxFrameRate >= target
            }) {
                let duration = CMTime(value: 1, timescale: CMTimeScale(target))
                device.activeVideoMinFrameDuration = duration
                device.activeVideoMaxFrameDuration = duration
            }
        } catch {
            Log.camera.error("设置相机格式失败: \(error.localizedDescription)")
        }
    }

    private static func applyMaxPhotoDimensions(
        to output: AVCapturePhotoOutput,
        device: AVCaptureDevice
    ) {
        let largest = device.activeFormat.supportedMaxPhotoDimensions.max { lhs, rhs in
            Int(lhs.width) * Int(lhs.height) < Int(rhs.width) * Int(rhs.height)
        }
        guard let largest, largest.width > 0, largest.height > 0 else { return }
        output.maxPhotoDimensions = largest
        Log.camera.info(
            "拍照尺寸: \(largest.width)x\(largest.height)"
        )
    }

    private func applyConnectionSettings(position: AVCaptureDevice.Position) {
        guard let connection = videoOutput.connection(with: .video) else { return }
        if connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        connection.isVideoMirrored = position == .front
    }

    private func observeSessionIfNeeded() {
        guard !isObserving else { return }
        isObserving = true
        let center = NotificationCenter.default
        center.addObserver(
            forName: .AVCaptureSessionWasInterrupted,
            object: session,
            queue: .main
        ) { [weak self] _ in
            self?.onStateChange?(.interrupted)
        }
        center.addObserver(
            forName: .AVCaptureSessionInterruptionEnded,
            object: session,
            queue: .main
        ) { [weak self] _ in
            self?.onStateChange?(.running)
        }
        center.addObserver(
            forName: .AVCaptureSessionRuntimeError,
            object: session,
            queue: .main
        ) { [weak self] notification in
            let error = notification.userInfo?[AVCaptureSessionErrorKey] as? Error
            let message = error?.localizedDescription ?? "相机运行时错误"
            self?.onStateChange?(.failed(.configurationFailed(message)))
        }
    }

    private static func device(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .builtInDualCamera, .builtInTripleCamera],
            mediaType: .video,
            position: position
        ).devices.first
    }
}

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onFrame?(CIImage(cvPixelBuffer: buffer))
    }
}

extension CameraService: AVCapturePhotoCaptureDelegate {
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        let continuation: CheckedContinuation<CapturedPhoto, Error>?
        photoLock.lock()
        continuation = photoContinuation
        photoContinuation = nil
        photoLock.unlock()

        if let error {
            continuation?.resume(throwing: CameraError.captureFailed(error.localizedDescription))
            return
        }
        guard let image = Self.makeImage(from: photo) else {
            continuation?.resume(throwing: CameraError.captureFailed("照片数据为空"))
            return
        }
        let rawOrientation = (photo.metadata[kCGImagePropertyOrientation as String] as? NSNumber)?.uint32Value
        // App 只支持竖屏，缺失时按「竖拍」处理。
        let orientation = rawOrientation.flatMap(CGImagePropertyOrientation.init(rawValue:)) ?? .right
        continuation?.resume(
            returning: CapturedPhoto(
                image: image,
                orientation: orientation,
                metadata: photo.metadata
            )
        )
    }

    /// 优先用解码后的像素缓冲，避免多一次 JPEG/HEIF 解码带来的画质损失。
    private static func makeImage(from photo: AVCapturePhoto) -> CIImage? {
        if let buffer = photo.pixelBuffer {
            return CIImage(cvPixelBuffer: buffer)
        }
        if let cgImage = photo.cgImageRepresentation() {
            return CIImage(cgImage: cgImage)
        }
        if let data = photo.fileDataRepresentation(),
           let source = CGImageSourceCreateWithData(data as CFData, nil),
           let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            return CIImage(cgImage: cgImage)
        }
        return nil
    }
}
