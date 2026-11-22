import AudioToolbox
import AVFoundation
import CoreImage
import CoreMedia
import CoreVideo
import ImageIO

/// 前后双摄：后摄主画面，前摄贴在右上角。
/// 用 AVCaptureMultiCamSession 同时驱动两颗摄像头，预览和照片都由这里合成。
final class DualCameraService: NSObject, CameraServicing {
    static var isSupported: Bool { AVCaptureMultiCamSession.isMultiCamSupported }

    private let session = AVCaptureMultiCamSession()
    private let sessionQueue = DispatchQueue(label: "com.filtercam.dual.session")
    private let videoQueue = DispatchQueue(label: "com.filtercam.dual.video", qos: .userInitiated)
    private let audioQueue = DispatchQueue(label: "com.filtercam.dual.audio", qos: .userInitiated)
    private let writerQueue = DispatchQueue(label: "com.filtercam.dual.writer", qos: .userInitiated)
    private let photoLock = NSLock()

    private var backInput: AVCaptureDeviceInput?
    private var frontInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?

    private let backVideoOutput = AVCaptureVideoDataOutput()
    private let frontVideoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private let backPhotoOutput = AVCapturePhotoOutput()
    private let frontPhotoOutput = AVCapturePhotoOutput()

    private var captureMode: CaptureMode = .photo
    private var flashMode: FlashMode = .auto
    private var isConfigured = false
    private var isObserving = false

    private var latestBack: CIImage?
    private var latestFront: CIImage?
    private let frameLock = NSLock()

    private var pipCenter = PiPLayout.defaultCenter
    private let pipLock = NSLock()

    private let zoomLock = NSLock()
    private var pendingZoom: CGFloat?
    private var isZoomDraining = false

    private var photoContinuation: CheckedContinuation<CapturedPhoto, Error>?
    private var pendingBack: CapturedPhoto?
    private var pendingFront: CapturedPhoto?

    // 实时写入：后摄帧作为时钟，合成后直接写 AVAssetWriter。
    // AVCaptureMovieFileOutput 在前后双摄下不能同时录两路，所以视频走这条链路。
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private var assetWriter: AVAssetWriter?
    private var writerVideoInput: AVAssetWriterInput?
    private var writerAudioInput: AVAssetWriterInput?
    private var writerAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var writerURL: URL?
    private var writerSize = CGSize(width: 1080, height: 1920)
    private var writerStarted = false
    private var writerActive = false
    private var writerStartPTS = CMTime.zero
    private var writerLastPTS = CMTime.zero

    var onFrame: ((CIImage) -> Void)?
    var onStateChange: ((CameraRuntimeState) -> Void)?

    var isDualCamera: Bool { true }

    // MARK: - 生命周期

    func start() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async {
                CrashLogger.breadcrumb("双摄: 开始启动")
                do {
                    try self.configureIfNeeded()
                    self.observeIfNeeded()
                    if !self.session.isRunning {
                        CrashLogger.breadcrumb("双摄: startRunning")
                        self.session.startRunning()
                        CrashLogger.breadcrumb("双摄: startRunning 返回")
                    }
                    if let back = self.backInput?.device {
                        Self.configureFocus(for: back)
                    }
                    if let front = self.frontInput?.device {
                        Self.configureFocus(for: front)
                    }
                    self.onStateChange?(.running)
                    CrashLogger.breadcrumb("双摄: 已运行")
                    continuation.resume()
                } catch {
                    CrashLogger.breadcrumb("双摄: 启动失败 \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stop() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sessionQueue.async {
                CrashLogger.breadcrumb("双摄: 开始停止")
                self.cancelWriter()
                if self.session.isRunning {
                    self.session.stopRunning()
                }
                CrashLogger.breadcrumb("双摄: 已停止")
                self.onStateChange?(.idle)
                continuation.resume()
            }
        }
    }

    func switchCamera() async throws {
        // 双摄模式下两颗摄像头已经同时开启，翻转按钮不做切换。
    }

    func setFlashMode(_ mode: FlashMode) {
        sessionQueue.async { self.flashMode = mode }
    }

    func setPhotoResolution(_ resolution: PhotoResolution) {
        // 双摄固定 12MP，最高像素档不可用。
    }

    /// 小窗位置：显示坐标系的归一化点（原点左上）。
    func setPiPCenter(_ center: CGPoint) {
        pipLock.lock()
        pipCenter = center
        pipLock.unlock()
    }

    private var currentPiPCenter: CGPoint {
        pipLock.lock()
        defer { pipLock.unlock() }
        return pipCenter
    }

    var isLivePhotoCaptureSupported: Bool { false }

    func setLivePhotoEnabled(_ enabled: Bool) async -> Bool { false }

    // MARK: - 配置

    private func configureIfNeeded() throws {
        guard !isConfigured else { return }
        guard AVCaptureMultiCamSession.isMultiCamSupported else {
            throw CameraError.configurationFailed("这台设备不支持前后双摄")
        }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        CrashLogger.breadcrumb("双摄: beginConfiguration")

        guard let backDevice = Self.device(.back),
              let frontDevice = Self.device(.front) else {
            throw CameraError.noCameraAvailable
        }

        Self.applyVideoFormat(for: backDevice, width: 1920, height: 1080)
        Self.applyVideoFormat(for: frontDevice, width: 1920, height: 1080)
        CrashLogger.breadcrumb("双摄: 格式已设置")

        let back = try AVCaptureDeviceInput(device: backDevice)
        let front = try AVCaptureDeviceInput(device: frontDevice)
        guard session.canAddInput(back), session.canAddInput(front) else {
            throw CameraError.configurationFailed("无法添加前后摄像头")
        }
        session.addInputWithNoConnections(back)
        session.addInputWithNoConnections(front)
        backInput = back
        frontInput = front
        Self.configureFocus(for: backDevice)
        Self.configureFocus(for: frontDevice)
        CrashLogger.breadcrumb("双摄: 输入已添加")

        for output in [backVideoOutput, frontVideoOutput] {
            output.alwaysDiscardsLateVideoFrames = true
            output.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            guard session.canAddOutput(output) else {
                throw CameraError.configurationFailed("无法添加视频输出")
            }
            session.addOutputWithNoConnections(output)
        }
        backVideoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        frontVideoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        CrashLogger.breadcrumb("双摄: 视频输出已添加")

        guard session.canAddOutput(backPhotoOutput),
              session.canAddOutput(frontPhotoOutput) else {
            throw CameraError.configurationFailed("无法添加照片输出")
        }
        session.addOutputWithNoConnections(backPhotoOutput)
        session.addOutputWithNoConnections(frontPhotoOutput)
        backPhotoOutput.maxPhotoQualityPrioritization = .quality
        frontPhotoOutput.maxPhotoQualityPrioritization = .quality
        CrashLogger.breadcrumb("双摄: 照片输出已添加")

        guard addConnection(input: back, output: backVideoOutput, mirrored: false) != nil,
              addConnection(input: front, output: frontVideoOutput, mirrored: true) != nil else {
            throw CameraError.configurationFailed("无法连接前后摄像头预览")
        }
        guard addConnection(input: back, output: backPhotoOutput, mirrored: false) != nil,
              addConnection(input: front, output: frontPhotoOutput, mirrored: true) != nil else {
            throw CameraError.configurationFailed("无法连接前后摄像头拍照")
        }
        // 必须先连上视频源设备，才能设置 maxPhotoDimensions，否则会抛异常。
        Self.applyMaxPhotoDimensions(to: backPhotoOutput, device: backDevice)
        Self.applyMaxPhotoDimensions(to: frontPhotoOutput, device: frontDevice)
        CrashLogger.breadcrumb("双摄: 连接已建立")

        // 双路 1080p 超出硬件预算时退回 720p。
        if session.hardwareCost > 1.0 {
            Log.camera.info("双摄 1080p 超出预算，退回 720p")
            Self.applyVideoFormat(for: backDevice, width: 1280, height: 720)
            Self.applyVideoFormat(for: frontDevice, width: 1280, height: 720)
            // 格式变了，拍照上限也要跟着改，否则拍照时会因尺寸不合法崩溃。
            Self.applyMaxPhotoDimensions(to: backPhotoOutput, device: backDevice)
            Self.applyMaxPhotoDimensions(to: frontPhotoOutput, device: frontDevice)
        }
        Log.camera.info("双摄硬件占用: \(self.session.hardwareCost)")
        CrashLogger.breadcrumb("双摄: 硬件占用 \(self.session.hardwareCost)")
        guard session.hardwareCost <= 1.0 else {
            throw CameraError.configurationFailed("双摄超出硬件能力，请关闭其他相机应用后重试")
        }

        isConfigured = true
    }

    @discardableResult
    private func addConnection(
        input: AVCaptureDeviceInput,
        output: AVCaptureOutput,
        mirrored: Bool
    ) -> AVCaptureConnection? {
        guard let port = input.ports(
            for: .video,
            sourceDeviceType: input.device.deviceType,
            sourceDevicePosition: input.device.position
        ).first else { return nil }

        let connection = AVCaptureConnection(inputPorts: [port], output: output)
        guard session.canAddConnection(connection) else {
            Log.camera.error("双摄连接添加失败: \(type(of: output))")
            CrashLogger.breadcrumb("双摄: 连接被拒绝 \(type(of: output))")
            return nil
        }
        session.addConnection(connection)
        CrashLogger.breadcrumb("双摄: 连接完成 \(type(of: output))")
        // 多摄会话里必须先关闭自动镜像，再手动设置，否则会抛异常。
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = mirrored
        }
        if connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        return connection
    }

    // MARK: - 模式

    func setCaptureMode(_ mode: CaptureMode) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async {
                CrashLogger.breadcrumb("双摄: 切换模式 \(mode)")
                do {
                    try self.applyCaptureMode(mode)
                    continuation.resume()
                } catch {
                    CrashLogger.breadcrumb("双摄: 切换模式失败 \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func applyCaptureMode(_ mode: CaptureMode) throws {
        guard mode != captureMode else { return }
        guard !isWriterActive else {
            throw CameraError.captureFailed("录制中不能切换模式")
        }

        session.beginConfiguration()
        do {
            switch mode {
            case .video:
                removePhotoOutputs()
                addAudioIfPossible()
            case .photo:
                removeAudio()
                try addPhotoOutputsIfNeeded()
            }
            session.commitConfiguration()
        } catch {
            session.commitConfiguration()
            throw error
        }
        captureMode = mode
    }

    private var isWriterActive: Bool {
        writerQueue.sync { writerActive }
    }

    private func addPhotoOutputsIfNeeded() throws {
        guard let backInput, let frontInput else { return }
        if !session.outputs.contains(where: { $0 === backPhotoOutput }) {
            guard session.canAddOutput(backPhotoOutput) else {
                throw CameraError.configurationFailed("无法添加后摄照片输出")
            }
            session.addOutputWithNoConnections(backPhotoOutput)
            guard addConnection(input: backInput, output: backPhotoOutput, mirrored: false) != nil else {
                throw CameraError.configurationFailed("无法连接后摄拍照")
            }
            Self.applyMaxPhotoDimensions(to: backPhotoOutput, device: backInput.device)
        }
        if !session.outputs.contains(where: { $0 === frontPhotoOutput }) {
            guard session.canAddOutput(frontPhotoOutput) else {
                throw CameraError.configurationFailed("无法添加前摄照片输出")
            }
            session.addOutputWithNoConnections(frontPhotoOutput)
            guard addConnection(input: frontInput, output: frontPhotoOutput, mirrored: true) != nil else {
                throw CameraError.configurationFailed("无法连接前摄拍照")
            }
            Self.applyMaxPhotoDimensions(to: frontPhotoOutput, device: frontInput.device)
        }
    }

    private func removePhotoOutputs() {
        if session.outputs.contains(where: { $0 === backPhotoOutput }) {
            session.removeOutput(backPhotoOutput)
        }
        if session.outputs.contains(where: { $0 === frontPhotoOutput }) {
            session.removeOutput(frontPhotoOutput)
        }
    }

    /// 视频模式挂一路麦克风数据输出；没授权也能录无声视频。
    private func addAudioIfPossible() {
        guard audioInput == nil else { return }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
              let device = AVCaptureDevice.default(for: .audio),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInputWithNoConnections(input)

        guard session.canAddOutput(audioOutput) else {
            session.removeInput(input)
            return
        }
        session.addOutputWithNoConnections(audioOutput)

        guard let port = input.ports(
            for: .audio,
            sourceDeviceType: device.deviceType,
            sourceDevicePosition: .unspecified
        ).first else {
            session.removeOutput(audioOutput)
            session.removeInput(input)
            return
        }
        let connection = AVCaptureConnection(inputPorts: [port], output: audioOutput)
        guard session.canAddConnection(connection) else {
            session.removeOutput(audioOutput)
            session.removeInput(input)
            return
        }
        session.addConnection(connection)
        audioOutput.setSampleBufferDelegate(self, queue: audioQueue)
        audioInput = input
    }

    private func removeAudio() {
        audioOutput.setSampleBufferDelegate(nil, queue: nil)
        if session.outputs.contains(where: { $0 === audioOutput }) {
            session.removeOutput(audioOutput)
        }
        if let audioInput {
            session.removeInput(audioInput)
            self.audioInput = nil
        }
    }

    // MARK: - 录制

    func startRecording() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async {
                do {
                    if self.captureMode != .video {
                        try self.applyCaptureMode(.video)
                    }
                } catch {
                    continuation.resume(throwing: error)
                    return
                }
                guard self.captureMode == .video else {
                    continuation.resume(throwing: CameraError.captureFailed("当前不是视频模式"))
                    return
                }
                do {
                    try self.writerQueue.sync { try self.beginWriter() }
                    CrashLogger.breadcrumb("双摄: 开始录制")
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stopRecording() async throws -> RecordedVideo {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<RecordedVideo, Error>) in
            writerQueue.async {
                guard self.writerActive,
                      let writer = self.assetWriter,
                      let url = self.writerURL else {
                    continuation.resume(throwing: CameraError.captureFailed("当前没有在录制"))
                    return
                }
                self.writerActive = false
                self.writerVideoInput?.markAsFinished()
                self.writerAudioInput?.markAsFinished()
                let rawDuration = CMTimeSubtract(self.writerLastPTS, self.writerStartPTS)
                let duration = rawDuration.isValid ? rawDuration : .zero
                let size = self.writerSize
                writer.finishWriting {
                    if writer.status == .completed {
                        continuation.resume(returning: RecordedVideo(
                            url: url,
                            duration: duration,
                            pixelWidth: Int(abs(size.width)),
                            pixelHeight: Int(abs(size.height)),
                            frontURL: nil
                        ))
                        self.writerQueue.async { self.resetWriter(deleteFile: false) }
                    } else {
                        continuation.resume(throwing: writer.error ?? CameraError.captureFailed("视频写入失败"))
                        self.writerQueue.async { self.resetWriter(deleteFile: true) }
                    }
                }
            }
        }
    }

    private func beginWriter() throws {
        guard !writerActive else {
            throw CameraError.captureFailed("正在录制中")
        }
        // 只清状态，不删旧文件：上一段视频可能还在保存队列里。
        resetWriter(deleteFile: false)

        frameLock.lock()
        let size = latestBack?.extent.size ?? CGSize(width: 1080, height: 1920)
        frameLock.unlock()
        writerSize = CGSize(width: abs(size.width), height: abs(size.height))

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("filtercam-dual-\(UUID().uuidString).mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(writerSize.width),
            AVVideoHeightKey: Int(writerSize.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 16_000_000,
                AVVideoExpectedSourceFrameRateKey: 30,
                AVVideoMaxKeyFrameIntervalKey: 60
            ]
        ]
        let videoWriter = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoWriter.expectsMediaDataInRealTime = true
        guard writer.canAdd(videoWriter) else {
            throw CameraError.captureFailed("无法创建视频写入")
        }
        writer.add(videoWriter)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoWriter,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey as String: Int(writerSize.width),
                kCVPixelBufferHeightKey as String: Int(writerSize.height)
            ]
        )

        var audioWriter: AVAssetWriterInput?
        if audioInput != nil {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: 1,
                AVSampleRateKey: 44_100,
                AVEncoderBitRateKey: 128_000
            ]
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            input.expectsMediaDataInRealTime = true
            if writer.canAdd(input) {
                writer.add(input)
                audioWriter = input
            }
        }

        guard writer.startWriting() else {
            throw writer.error ?? CameraError.captureFailed("视频写入启动失败")
        }

        assetWriter = writer
        writerVideoInput = videoWriter
        writerAudioInput = audioWriter
        writerAdaptor = adaptor
        writerURL = url
        writerStarted = false
        writerActive = true
        writerStartPTS = .zero
        writerLastPTS = .zero
    }

    private func appendVideo(_ image: CIImage, at pts: CMTime) {
        guard writerActive,
              let writer = assetWriter,
              writer.status == .writing,
              let input = writerVideoInput,
              input.isReadyForMoreMediaData,
              let adaptor = writerAdaptor else { return }

        if !writerStarted {
            writer.startSession(atSourceTime: pts)
            writerStartPTS = pts
            writerStarted = true
        }
        writerLastPTS = pts

        guard let pool = adaptor.pixelBufferPool else { return }
        var buffer: CVPixelBuffer?
        _ = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer)
        guard let destination = buffer else { return }

        let extent = image.extent
        let normalized = image.transformed(
            by: CGAffineTransform(translationX: -extent.origin.x, y: -extent.origin.y)
        )
        ciContext.render(
            normalized,
            to: destination,
            bounds: CGRect(origin: .zero, size: writerSize),
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        adaptor.append(destination, withPresentationTime: pts)
    }

    private func appendAudio(_ sampleBuffer: CMSampleBuffer) {
        guard writerActive,
              writerStarted,
              let input = writerAudioInput,
              input.isReadyForMoreMediaData else { return }
        input.append(sampleBuffer)
    }

    private func cancelWriter() {
        writerQueue.sync {
            guard writerActive || assetWriter != nil else { return }
            writerActive = false
            writerVideoInput?.markAsFinished()
            writerAudioInput?.markAsFinished()
            if let writer = assetWriter, writer.status == .writing {
                writer.cancelWriting()
            }
            resetWriter(deleteFile: true)
        }
    }

    private func resetWriter(deleteFile: Bool) {
        if deleteFile, let writerURL {
            try? FileManager.default.removeItem(at: writerURL)
        }
        assetWriter = nil
        writerVideoInput = nil
        writerAudioInput = nil
        writerAdaptor = nil
        writerURL = nil
        writerStarted = false
        writerActive = false
        writerStartPTS = .zero
        writerLastPTS = .zero
    }

    // MARK: - 照片

    func capturePhoto() async throws -> CapturedPhoto {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CapturedPhoto, Error>) in
            sessionQueue.async {
                self.photoLock.lock()
                let isBusy = self.photoContinuation != nil
                if !isBusy {
                    self.photoContinuation = continuation
                    self.pendingBack = nil
                    self.pendingFront = nil
                }
                self.photoLock.unlock()
                guard !isBusy else {
                    continuation.resume(throwing: CameraError.captureFailed("上一张照片仍在处理中"))
                    return
                }

                let backSettings = self.makePhotoSettings(for: self.backPhotoOutput, flash: self.flashMode)
                let frontSettings = self.makePhotoSettings(for: self.frontPhotoOutput, flash: .off)
                CrashLogger.breadcrumb("双摄: 拍照 capturePhoto")
                self.backPhotoOutput.capturePhoto(with: backSettings, delegate: self)
                self.frontPhotoOutput.capturePhoto(with: frontSettings, delegate: self)
            }
        }
    }

    private func makePhotoSettings(
        for output: AVCapturePhotoOutput,
        flash: FlashMode
    ) -> AVCapturePhotoSettings {
        let settings: AVCapturePhotoSettings
        if output.availablePhotoCodecTypes.contains(.hevc) {
            settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
        } else {
            settings = AVCapturePhotoSettings()
        }
        settings.photoQualityPrioritization = .quality
        let allowed = output.maxPhotoDimensions
        if allowed.width > 0, allowed.height > 0 {
            settings.maxPhotoDimensions = allowed
        }
        if output.supportedFlashModes.contains(flash.avMode) {
            settings.flashMode = flash.avMode
        }
        return settings
    }

    // MARK: - 对焦（只作用在后摄）

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

    private func applyFocus(at point: CGPoint) throws {
        guard let device = backInput?.device else {
            throw CameraError.configurationFailed("相机未就绪")
        }
        let clamped = CGPoint(x: min(max(point.x, 0), 1), y: min(max(point.y, 0), 1))
        guard (try? device.lockForConfiguration()) != nil else {
            throw CameraError.captureFailed("无法锁定相机配置")
        }
        defer { device.unlockForConfiguration() }
        if device.isFocusPointOfInterestSupported {
            device.focusPointOfInterest = clamped
            if device.isFocusModeSupported(.autoFocus) { device.focusMode = .autoFocus }
        }
        if device.isExposurePointOfInterestSupported {
            device.exposurePointOfInterest = clamped
            if device.isExposureModeSupported(.autoExpose) { device.exposureMode = .autoExpose }
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

    private func applyManualFocus(_ lensPosition: Float) throws {
        guard let device = backInput?.device else {
            throw CameraError.configurationFailed("相机未就绪")
        }
        guard device.isFocusModeSupported(.locked) else {
            throw CameraError.captureFailed("当前摄像头不支持手动对焦")
        }
        guard (try? device.lockForConfiguration()) != nil else {
            throw CameraError.captureFailed("无法锁定相机配置")
        }
        defer { device.unlockForConfiguration() }
        device.setFocusModeLocked(lensPosition: min(max(lensPosition, 0), 1))
        if device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
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

    private func applyContinuousFocus() throws {
        guard let device = backInput?.device else {
            throw CameraError.configurationFailed("相机未就绪")
        }
        guard (try? device.lockForConfiguration()) != nil else {
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

    // MARK: - 变焦（只作用于后摄主画面）

    var zoomRange: ClosedRange<CGFloat> {
        guard let device = backInput?.device else { return 1...1 }
        return device.minAvailableVideoZoomFactor...device.maxAvailableVideoZoomFactor
    }

    func setZoomFactor(_ factor: CGFloat) {
        // 合并高频请求，只应用最新值，拖动时不会越拖越滞后。
        zoomLock.lock()
        pendingZoom = factor
        let shouldSchedule = !isZoomDraining
        isZoomDraining = true
        zoomLock.unlock()
        guard shouldSchedule else { return }
        sessionQueue.async { self.drainZoom() }
    }

    private func drainZoom() {
        while true {
            zoomLock.lock()
            guard let value = pendingZoom else {
                isZoomDraining = false
                zoomLock.unlock()
                return
            }
            pendingZoom = nil
            zoomLock.unlock()
            applyZoom(value)
        }
    }

    private func applyZoom(_ factor: CGFloat) {
        guard let device = backInput?.device else { return }
        guard (try? device.lockForConfiguration()) != nil else { return }
        defer { device.unlockForConfiguration() }
        let clamped = min(
            max(factor, device.minAvailableVideoZoomFactor),
            device.maxAvailableVideoZoomFactor
        )
        device.videoZoomFactor = clamped
    }

    // MARK: - 设备与格式

    private static func device(_ position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: position
        ).devices.first
    }

    private static func applyVideoFormat(for device: AVCaptureDevice, width: Int32, height: Int32) {
        // 多摄会话只能使用 isMultiCamSupported == true 的格式。
        let multiCam = device.formats.filter { $0.isMultiCamSupported }
        guard !multiCam.isEmpty else {
            Log.camera.error("\(device.position.rawValue) 没有支持多摄的格式")
            return
        }
        let supports30 = { (format: AVCaptureDevice.Format) in
            format.videoSupportedFrameRateRanges.contains {
                $0.minFrameRate <= 30 && $0.maxFrameRate >= 30
            }
        }
        let exact = multiCam.filter { format in
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            return dims.width == width && dims.height == height && supports30(format)
        }
        let capped = multiCam.filter { format in
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            return dims.width <= 1920 && dims.height <= 1080 && supports30(format)
        }
        let best = exact.max { formatScore($0) < formatScore($1) }
            ?? capped.max { formatScore($0) < formatScore($1) }
            ?? multiCam.max { formatScore($0) < formatScore($1) }
        guard let best else { return }

        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            device.activeFormat = best
            let duration = CMTime(value: 1, timescale: 30)
            device.activeVideoMinFrameDuration = duration
            device.activeVideoMaxFrameDuration = duration
            let dims = CMVideoFormatDescriptionGetDimensions(best.formatDescription)
            Log.camera.info("双摄格式: \(dims.width)x\(dims.height) \(device.position.rawValue)")
        } catch {
            Log.camera.error("双摄设置格式失败: \(error.localizedDescription)")
        }
    }

    private static func photoArea(_ format: AVCaptureDevice.Format) -> Int {
        format.supportedMaxPhotoDimensions.reduce(0) { partial, dims in
            max(partial, Int(dims.width) * Int(dims.height))
        }
    }

    /// 同尺寸下优先 30fps 常规格式，避免选到 60fps 以上的高速格式。
    private static func formatScore(_ format: AVCaptureDevice.Format) -> (Int, Int) {
        let maxRate = format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
        return (photoArea(format), -Int(maxRate))
    }

    private static func configureFocus(for device: AVCaptureDevice) {
        guard (try? device.lockForConfiguration()) != nil else { return }
        defer { device.unlockForConfiguration() }

        if device.isFocusModeSupported(.continuousAutoFocus) {
            device.focusMode = .continuousAutoFocus
        } else if device.isFocusModeSupported(.autoFocus) {
            device.focusMode = .autoFocus
        }
        if device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
        }
    }

    private static func applyMaxPhotoDimensions(
        to output: AVCapturePhotoOutput,
        device: AVCaptureDevice
    ) {
        let limit = 12_000_000
        let sorted = device.activeFormat.supportedMaxPhotoDimensions.sorted {
            Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height)
        }
        guard let best = sorted.last(where: { Int($0.width) * Int($0.height) <= limit }) ?? sorted.first,
              best.width > 0, best.height > 0 else { return }
        output.maxPhotoDimensions = best
        Log.camera.info("双摄拍照尺寸: \(best.width)x\(best.height)")
    }

    private func observeIfNeeded() {
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
}

extension DualCameraService: AVCaptureVideoDataOutputSampleBufferDelegate,
                             AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        if output === audioOutput {
            writerQueue.sync {
                if writerActive {
                    appendAudio(sampleBuffer)
                }
            }
            return
        }

        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let image = CIImage(cvPixelBuffer: buffer)

        frameLock.lock()
        if output === backVideoOutput {
            latestBack = image
        } else {
            latestFront = image
        }
        let back = latestBack
        let front = latestFront
        frameLock.unlock()

        // 只跟随后摄的帧率合成，前摄帧只用来更新小窗。
        guard output === backVideoOutput, let back else { return }
        let composed = PiPComposer.compose(
            back: back,
            front: front,
            center: currentPiPCenter
        )
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        writerQueue.sync {
            if writerActive {
                appendVideo(composed, at: pts)
            }
        }
        onFrame?(composed)
    }
}

extension DualCameraService: AVCapturePhotoCaptureDelegate {
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        photoLock.lock()
        let continuation = photoContinuation
        if let error {
            photoContinuation = nil
            pendingBack = nil
            pendingFront = nil
            photoLock.unlock()
            continuation?.resume(throwing: CameraError.captureFailed(error.localizedDescription))
            return
        }
        guard let image = Self.makeImage(from: photo) else {
            photoContinuation = nil
            pendingBack = nil
            pendingFront = nil
            photoLock.unlock()
            continuation?.resume(throwing: CameraError.captureFailed("照片数据为空"))
            return
        }
        let rawOrientation = (photo.metadata[kCGImagePropertyOrientation as String] as? NSNumber)?.uint32Value
        let orientation = rawOrientation.flatMap(CGImagePropertyOrientation.init(rawValue:)) ?? .right
        let captured = CapturedPhoto(
            image: image,
            orientation: orientation,
            metadata: photo.metadata,
            livePhotoMovieURL: nil
        )
        if output === backPhotoOutput {
            pendingBack = captured
        } else {
            pendingFront = captured
        }

        let back = pendingBack
        let front = pendingFront
        var finished: CheckedContinuation<CapturedPhoto, Error>?
        if back != nil, front != nil {
            finished = photoContinuation
            photoContinuation = nil
            pendingBack = nil
            pendingFront = nil
        }
        photoLock.unlock()

        guard let finished, let back, let front else { return }

        let composed = Self.compose(back: back, front: front, center: currentPiPCenter)
        finished.resume(returning: composed)
    }

    private static func compose(
        back: CapturedPhoto,
        front: CapturedPhoto,
        center: CGPoint
    ) -> CapturedPhoto {
        let backImage = back.image.oriented(back.orientation)
        let frontImage = front.image.oriented(front.orientation)
        let composed = PiPComposer.compose(
            back: backImage,
            front: frontImage,
            center: center
        )
        return CapturedPhoto(
            image: composed,
            orientation: .up,
            metadata: back.metadata,
            livePhotoMovieURL: nil
        )
    }

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
