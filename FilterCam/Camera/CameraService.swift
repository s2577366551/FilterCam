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

        settings.maxPhotoDimensions = bestPhotoDimensions()
        settings.photoQualityPrioritization = .quality
        if photoOutput.supportedFlashModes.contains(flashMode.avMode) {
            settings.flashMode = flashMode.avMode
        }
        return settings
    }

    /// 取设备当前格式支持的最大拍照尺寸，并限制在输出端允许的范围内。
    private func bestPhotoDimensions() -> CMVideoDimensions {
        let allowed = photoOutput.maxPhotoDimensions
        let allowedArea = Int(allowed.width) * Int(allowed.height)

        guard let device = videoInput?.device else { return allowed }
        let candidates = device.activeFormat.supportedMaxPhotoDimensions
        let largest = candidates.max { lhs, rhs in
            Int(lhs.width) * Int(lhs.height) < Int(rhs.width) * Int(rhs.height)
        }
        guard let largest else { return allowed }
        if allowedArea > 0, Int(largest.width) * Int(largest.height) > allowedArea {
            return allowed
        }
        return largest
    }

    private func configureIfNeeded() throws {
        guard !isConfigured else { return }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        // 用 .photo 预设，让照片输出拿到设备的最大拍照分辨率（约 4032×3024），
        // 而不是被 1080p 视频预设限制。
        session.sessionPreset = .photo

        guard let device = Self.device(position: position) else {
            throw CameraError.noCameraAvailable
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
        applyConnectionSettings(position: newPosition)
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
