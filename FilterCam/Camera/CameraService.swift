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
    private let movieOutput = AVCaptureMovieFileOutput()

    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    private var position: AVCaptureDevice.Position = .back
    private var hasUltraWide = false
    private var isUsingUltraWide = false
    private var maxUIZoom: CGFloat = 1
    private var captureMode: CaptureMode = .photo
    private var isMovieOutputAdded = false
    private var flashMode: FlashMode = .auto
    private var photoResolution: PhotoResolution = .standard
    private var livePhotoEnabled = false
    private var awaitingLivePhotoMovie = false
    private var pendingCapturedPhoto: CapturedPhoto?
    private var pendingMovieURL: URL?
    private var isConfigured = false
    private var isObserving = false
    private let photoLock = NSLock()
    private var photoContinuation: CheckedContinuation<CapturedPhoto, Error>?
    private let recordingLock = NSLock()
    private var startRecordingContinuation: CheckedContinuation<Void, Error>?
    private var stopRecordingContinuation: CheckedContinuation<RecordedVideo, Error>?
    private var recordingStartDate: Date?
    private var recordingURL: URL?

    var onFrame: ((CIImage) -> Void)?
    var onStateChange: ((CameraRuntimeState) -> Void)?

    func start() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async {
                CrashLogger.breadcrumb("单摄: 开始启动")
                do {
                    try self.configureIfNeeded()
                    self.observeSessionIfNeeded()
                    if !self.session.isRunning {
                        CrashLogger.breadcrumb("单摄: startRunning")
                        self.session.startRunning()
                        CrashLogger.breadcrumb("单摄: startRunning 返回")
                    }
                    if let device = self.videoInput?.device {
                        Self.configureFocus(for: device)
                    }
                    self.onStateChange?(.running)
                    continuation.resume()
                } catch {
                    CrashLogger.breadcrumb("单摄: 启动失败 \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stop() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sessionQueue.async {
                CrashLogger.breadcrumb("单摄: 开始停止")
                if self.movieOutput.isRecording {
                    self.movieOutput.stopRecording()
                }
                if self.session.isRunning {
                    self.session.stopRunning()
                }
                CrashLogger.breadcrumb("单摄: 已停止")
                self.onStateChange?(.idle)
                continuation.resume()
            }
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

    var isLivePhotoCaptureSupported: Bool {
        photoOutput.isLivePhotoCaptureSupported
    }

    /// 开启/关闭实况。返回最终是否真的启用成功。
    /// 实况最高只支持 1200 万像素，所以开启时要把拍照上限调回标准档。
    func setLivePhotoEnabled(_ enabled: Bool) async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            sessionQueue.async {
                continuation.resume(returning: self.applyLivePhotoEnabled(enabled))
            }
        }
    }

    private func applyLivePhotoEnabled(_ enabled: Bool) -> Bool {
        guard let device = videoInput?.device else { return false }
        // 视频模式下没有实况照片。
        guard captureMode == .photo else {
            photoOutput.isLivePhotoCaptureEnabled = false
            livePhotoEnabled = false
            return false
        }

        if !enabled {
            session.beginConfiguration()
            if let format = Self.bestPhotoFormat(for: device) {
                Self.applyFormat(format, to: device)
            }
            if let largest = Self.largestPhotoDimensions(for: device.activeFormat) {
                photoOutput.maxPhotoDimensions = largest
            }
            session.commitConfiguration()

            photoOutput.isLivePhotoCaptureEnabled = false
            livePhotoEnabled = false
            return false
        }

        // 先把拍照上限降到 12MP 档，再检查是否支持。
        session.beginConfiguration()
        if let standard = Self.standardPhotoDimensions(for: device.activeFormat) {
            photoOutput.maxPhotoDimensions = standard
        }
        session.commitConfiguration()

        var supported = photoOutput.isLivePhotoCaptureSupported

        if !supported {
            // 兜底：退回系统 .photo 预设（苹果保证支持实况的配置）再试一次。
            session.beginConfiguration()
            session.sessionPreset = .photo
            session.commitConfiguration()
            supported = photoOutput.isLivePhotoCaptureSupported
            if let current = videoInput?.device,
               let largest = Self.largestPhotoDimensions(for: current.activeFormat) {
                Log.camera.info("实况模式拍照上限: \(largest.width)x\(largest.height)")
            }
        }

        photoOutput.isLivePhotoCaptureEnabled = supported
        livePhotoEnabled = supported
        return supported
    }

    // MARK: - 照片 / 视频模式

    func setCaptureMode(_ mode: CaptureMode) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async {
                do {
                    try self.applyCaptureMode(mode)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func applyCaptureMode(_ mode: CaptureMode) throws {
        guard mode != captureMode else { return }
        guard !movieOutput.isRecording else {
            throw CameraError.captureFailed("录制中不能切换模式")
        }

        session.beginConfiguration()
        do {
            switch mode {
            case .video:
                photoOutput.isLivePhotoCaptureEnabled = false
                livePhotoEnabled = false

                // 视频走系统视频预设，保证 MovieFileOutput 能正常编码。
                if session.canSetSessionPreset(.hd4K3840x2160) {
                    session.sessionPreset = .hd4K3840x2160
                } else if session.canSetSessionPreset(.hd1920x1080) {
                    session.sessionPreset = .hd1920x1080
                } else {
                    session.sessionPreset = .high
                }
                if let device = videoInput?.device {
                    Self.configureFocus(for: device)
                }

                addAudioInputIfPossible()

                if !isMovieOutputAdded {
                    guard session.canAddOutput(movieOutput) else {
                        throw CameraError.configurationFailed("无法添加录像输出")
                    }
                    session.addOutput(movieOutput)
                    movieOutput.movieFragmentInterval = .invalid
                    isMovieOutputAdded = true
                }

            case .photo:
                if isMovieOutputAdded {
                    session.removeOutput(movieOutput)
                    isMovieOutputAdded = false
                }
                if let audioInput {
                    session.removeInput(audioInput)
                    self.audioInput = nil
                }

                // 恢复拍照格式：视频尺寸不超过 12MP，同时拿到最大静态拍照尺寸。
                session.sessionPreset = .inputPriority
                if let device = videoInput?.device,
                   let format = Self.bestPhotoFormat(for: device) {
                    Self.applyFormat(format, to: device)
                    Self.applyMaxPhotoDimensions(to: photoOutput, device: device)
                    Self.configureFocus(for: device)
                } else {
                    session.sessionPreset = .photo
                }
            }
            session.commitConfiguration()
        } catch {
            session.commitConfiguration()
            throw error
        }

        captureMode = mode

        applyConnectionSettings(position: position)
        if mode == .video {
            applyMovieConnectionSettings()
        }
    }

    /// 录像输出没挂上时补挂一次。
    private func ensureMovieOutput() throws {
        guard !isMovieOutputAdded else { return }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        guard session.canAddOutput(movieOutput) else {
            throw CameraError.configurationFailed("无法添加录像输出")
        }
        session.addOutput(movieOutput)
        movieOutput.movieFragmentInterval = .invalid
        isMovieOutputAdded = true
    }

    /// 只在用户已授权麦克风时加入音频输入；拒绝授权也能录无声视频。
    private func addAudioInputIfPossible() {        guard audioInput == nil else { return }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
              let device = AVCaptureDevice.default(for: .audio),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)
        audioInput = input
    }

    private func applyMovieConnectionSettings() {
        guard let connection = movieOutput.connection(with: .video) else { return }
        if connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        connection.isVideoMirrored = position == .front
        if connection.isVideoStabilizationSupported {
            connection.preferredVideoStabilizationMode = .auto
        }
    }

    func startRecording() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async {
                do {
                    // 模式状态不同步时兜底，避免点了录制才报“不是视频模式”。
                    if self.captureMode != .video {
                        try self.applyCaptureMode(.video)
                    } else {
                        try self.ensureMovieOutput()
                    }
                } catch {
                    continuation.resume(throwing: error)
                    return
                }
                guard self.captureMode == .video, self.isMovieOutputAdded else {
                    continuation.resume(throwing: CameraError.captureFailed("当前不是视频模式"))
                    return
                }
                guard !self.movieOutput.isRecording else {
                    continuation.resume(throwing: CameraError.captureFailed("正在录制中"))
                    return
                }
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("filtercam-record-\(UUID().uuidString).mov")
                self.recordingURL = url
                self.recordingStartDate = Date()

                self.recordingLock.lock()
                self.startRecordingContinuation = continuation
                self.recordingLock.unlock()

                self.applyMovieConnectionSettings()
                self.movieOutput.startRecording(to: url, recordingDelegate: self)
            }
        }
    }

    func stopRecording() async throws -> RecordedVideo {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<RecordedVideo, Error>) in
            sessionQueue.async {
                guard self.movieOutput.isRecording else {
                    continuation.resume(throwing: CameraError.captureFailed("当前没有在录制"))
                    return
                }
                self.recordingLock.lock()
                self.stopRecordingContinuation = continuation
                self.recordingLock.unlock()
                self.movieOutput.stopRecording()
            }
        }
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
                self.awaitingLivePhotoMovie = self.livePhotoEnabled
                    && self.photoOutput.isLivePhotoCaptureSupported
                self.pendingCapturedPhoto = nil
                self.pendingMovieURL = nil
                if self.awaitingLivePhotoMovie {
                    let url = FileManager.default.temporaryDirectory
                        .appendingPathComponent("filtercam-live-\(UUID().uuidString).mov")
                    self.pendingMovieURL = url
                    settings.livePhotoMovieFileURL = url
                }
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

        // 实况照片不支持最高像素档，自动按标准档拍。
        let effectiveResolution: PhotoResolution = livePhotoEnabled ? .standard : photoResolution
        settings.maxPhotoDimensions = photoDimensions(for: effectiveResolution)
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

    // MARK: - 变焦（0.5× 走超广角，1× 以上走主摄）

    /// 返回界面倍率范围：有超广角时从 0.5 起。
    var zoomRange: ClosedRange<CGFloat> {
        guard let device = videoInput?.device else { return 1...1 }
        let low: CGFloat = (position == .back && hasUltraWide) ? 0.5 : 1
        let high = isUsingUltraWide ? maxUIZoom : max(device.maxAvailableVideoZoomFactor, 1)
        return low...max(high, low)
    }

    func setZoomFactor(_ factor: CGFloat) {
        sessionQueue.async {
            self.applyZoom(factor)
        }
    }

    private func applyZoom(_ factor: CGFloat) {
        let range = zoomRange
        let ui = min(max(factor, range.lowerBound), range.upperBound)

        // 录制中不换镜头，避免中断录像。
        if position == .back, hasUltraWide, !movieOutput.isRecording {
            let wantsUltraWide = isUsingUltraWide ? ui < 0.98 : ui < 0.92
            if wantsUltraWide != isUsingUltraWide {
                do {
                    try switchLens(toUltraWide: wantsUltraWide)
                } catch {
                    Log.camera.error("切换超广角失败: \(error.localizedDescription)")
                }
            }
        }

        guard let device = videoInput?.device else { return }
        guard (try? device.lockForConfiguration()) != nil else { return }
        defer { device.unlockForConfiguration() }

        // 超广角镜头的 1.0 对应界面 0.5×，所以界面倍率要乘 2。
        let raw = isUsingUltraWide ? ui * 2 : ui
        device.videoZoomFactor = min(
            max(raw, device.minAvailableVideoZoomFactor),
            device.maxAvailableVideoZoomFactor
        )
    }

    /// 在超广角和主摄之间换输入；保持视频/照片/录像连接可用。
    private func switchLens(toUltraWide: Bool) throws {
        guard let device = toUltraWide ? Self.ultraWideDevice() : Self.device(position: .back) else {
            throw CameraError.noCameraAvailable
        }
        let input = try AVCaptureDeviceInput(device: device)

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        let previous = videoInput
        if let previous {
            session.removeInput(previous)
        }
        guard session.canAddInput(input) else {
            if let previous {
                session.addInput(previous)
            }
            throw CameraError.configurationFailed("无法切换镜头")
        }
        session.addInput(input)
        videoInput = input
        isUsingUltraWide = toUltraWide

        if captureMode == .photo {
            if let format = Self.bestPhotoFormat(for: device) {
                Self.applyFormat(format, to: device)
            }
            Self.applyMaxPhotoDimensions(to: photoOutput, device: device)
            if livePhotoEnabled, let standard = Self.standardPhotoDimensions(for: device.activeFormat) {
                photoOutput.maxPhotoDimensions = standard
            }
        }
        applyConnectionSettings(position: position)
        if captureMode == .video {
            applyMovieConnectionSettings()
        }
        Self.configureFocus(for: device)
        Log.camera.info("切换镜头: \(toUltraWide ? "超广角" : "主摄")")
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
        if position == .back {
            hasUltraWide = Self.ultraWideDevice() != nil
        }
        maxUIZoom = device.maxAvailableVideoZoomFactor
        isUsingUltraWide = false
        Self.configureFocus(for: device)

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
        isUsingUltraWide = false
        hasUltraWide = newPosition == .back && Self.ultraWideDevice() != nil
        maxUIZoom = device.maxAvailableVideoZoomFactor
        if captureMode == .photo {
            if let format = Self.bestPhotoFormat(for: device) {
                Self.applyFormat(format, to: device)
            }
            Self.applyMaxPhotoDimensions(to: photoOutput, device: device)
            // 实况模式下拍照上限必须保持在 12MP 档。
            if livePhotoEnabled, let standard = Self.standardPhotoDimensions(for: device.activeFormat) {
                photoOutput.maxPhotoDimensions = standard
            }
        }
        // 换摄像头后回到连续自动对焦，避免沿用上一颗镜头的锁定状态。
        Self.configureFocus(for: device)
        if (try? device.lockForConfiguration()) != nil {
            device.videoZoomFactor = max(1, device.minAvailableVideoZoomFactor)
            device.unlockForConfiguration()
        }
        applyConnectionSettings(position: newPosition)
        applyMovieConnectionSettings()
    }

    /// 打开自动对焦/自动曝光。前置镜头默认可能是锁定状态，会一直发虚。
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

    // MARK: - 格式选择

    /// 在视频尺寸不超过 12MP 的格式里，挑拍照尺寸最大的那个。
    /// 同分时优先视频分辨率更高的格式：前置镜头很多格式都能拍 12MP，
    /// 如果选到 720p 高速格式，预览就会被放大得发虚。
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
            formatScore(lhs) < formatScore(rhs)
        }
    }

    /// 排序优先级：拍照面积 → 视频分辨率 → 避开 120/240fps 高速格式。
    private static func formatScore(_ format: AVCaptureDevice.Format) -> (Int, Int, Int) {
        let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        let pixels = Int(dims.width) * Int(dims.height)
        let maxRate = format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
        let isHighSpeed = maxRate > 60 ? 0 : 1
        return (photoArea(format), pixels, isHighSpeed)
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
        guard let largest = largestPhotoDimensions(for: device.activeFormat),
              largest.width > 0, largest.height > 0 else { return }
        output.maxPhotoDimensions = largest
        Log.camera.info(
            "拍照尺寸: \(largest.width)x\(largest.height)"
        )
    }

    private static func largestPhotoDimensions(
        for format: AVCaptureDevice.Format
    ) -> CMVideoDimensions? {
        format.supportedMaxPhotoDimensions.max { lhs, rhs in
            Int(lhs.width) * Int(lhs.height) < Int(rhs.width) * Int(rhs.height)
        }
    }

    /// 不超过 1200 万像素的最大档（实况照片的上限）。
    private static func standardPhotoDimensions(
        for format: AVCaptureDevice.Format
    ) -> CMVideoDimensions? {
        let limit = 12_000_000
        let sorted = format.supportedMaxPhotoDimensions.sorted {
            Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height)
        }
        return sorted.last { Int($0.width) * Int($0.height) <= limit } ?? sorted.first
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
        // 固定用物理广角镜头，保证 1× 就是主摄；虚拟多摄设备的 raw 倍率语义不同。
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: position
        ).devices.first
    }

    private static func ultraWideDevice() -> AVCaptureDevice? {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInUltraWideCamera],
            mediaType: .video,
            position: .back
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

extension CameraService: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(
        _ output: AVCaptureFileOutput,
        didStartRecordingTo fileURL: URL,
        from connections: [AVCaptureConnection]
    ) {
        recordingLock.lock()
        let continuation = startRecordingContinuation
        startRecordingContinuation = nil
        recordingLock.unlock()
        continuation?.resume()
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        recordingLock.lock()
        let start = startRecordingContinuation
        startRecordingContinuation = nil
        let stop = stopRecordingContinuation
        stopRecordingContinuation = nil
        recordingStartDate = nil
        recordingURL = nil
        recordingLock.unlock()

        // AVFoundation 用这个 key 表示「虽然报错，但文件是完整的」。
        let finishedOK: Bool = {
            guard let error = error as NSError? else { return true }
            if let flag = error.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool {
                return flag
            }
            return false
        }()

        if let start {
            start.resume(throwing: error ?? CameraError.captureFailed("录制失败"))
            try? FileManager.default.removeItem(at: outputFileURL)
            return
        }

        guard let stop else {
            // 没有等待方（例如异常中断），清掉临时文件。
            try? FileManager.default.removeItem(at: outputFileURL)
            return
        }

        guard finishedOK, FileManager.default.fileExists(atPath: outputFileURL.path) else {
            try? FileManager.default.removeItem(at: outputFileURL)
            stop.resume(
                throwing: CameraError.captureFailed(error?.localizedDescription ?? "录制失败")
            )
            return
        }

        let asset = AVURLAsset(url: outputFileURL)
        let track = asset.tracks(withMediaType: .video).first
        let natural = track?.naturalSize ?? .zero
        stop.resume(
            returning: RecordedVideo(
                url: outputFileURL,
                duration: asset.duration,
                pixelWidth: Int(abs(natural.width)),
                pixelHeight: Int(abs(natural.height))
            )
        )
    }
}

extension CameraService: AVCapturePhotoCaptureDelegate {
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error {
            finishCapture(throwing: CameraError.captureFailed(error.localizedDescription))
            return
        }
        guard let image = Self.makeImage(from: photo) else {
            finishCapture(throwing: CameraError.captureFailed("照片数据为空"))
            return
        }
        let rawOrientation = (photo.metadata[kCGImagePropertyOrientation as String] as? NSNumber)?.uint32Value
        // App 只支持竖屏，缺失时按「竖拍」处理。
        let orientation = rawOrientation.flatMap(CGImagePropertyOrientation.init(rawValue:)) ?? .right
        let captured = CapturedPhoto(
            image: image,
            orientation: orientation,
            metadata: photo.metadata,
            livePhotoMovieURL: nil
        )

        photoLock.lock()
        let isLive = awaitingLivePhotoMovie
        if isLive {
            pendingCapturedPhoto = captured
        }
        let continuation = photoContinuation
        if !isLive {
            photoContinuation = nil
        }
        photoLock.unlock()

        guard isLive else {
            continuation?.resume(returning: captured)
            return
        }
        // 实况照片等 didFinishCaptureFor，确认视频文件写完再返回。
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
        error: Error?
    ) {
        photoLock.lock()
        let wasLive = awaitingLivePhotoMovie
        let photo = pendingCapturedPhoto
        let movieURL = pendingMovieURL
        let continuation = photoContinuation
        if wasLive {
            clearLiveState()
            photoContinuation = nil
        }
        photoLock.unlock()

        guard wasLive, let continuation else { return }

        if let error {
            if let photo {
                if let movieURL { try? FileManager.default.removeItem(at: movieURL) }
                continuation.resume(returning: photo)
            } else {
                continuation.resume(
                    throwing: CameraError.captureFailed(error.localizedDescription)
                )
            }
            return
        }
        guard let photo else {
            continuation.resume(throwing: CameraError.captureFailed("照片数据为空"))
            return
        }
        if let movieURL, FileManager.default.fileExists(atPath: movieURL.path) {
            continuation.resume(
                returning: CapturedPhoto(
                    image: photo.image,
                    orientation: photo.orientation,
                    metadata: photo.metadata,
                    livePhotoMovieURL: movieURL
                )
            )
        } else {
            // 视频没写出来就退回普通照片，避免整张照片丢失。
            if let movieURL { try? FileManager.default.removeItem(at: movieURL) }
            continuation.resume(returning: photo)
        }
    }

    /// 调用方必须已持有 photoLock。
    private func clearLiveState() {
        pendingCapturedPhoto = nil
        pendingMovieURL = nil
        awaitingLivePhotoMovie = false
    }

    private func finishCapture(throwing error: Error) {
        photoLock.lock()
        let continuation = photoContinuation
        photoContinuation = nil
        clearLiveState()
        photoLock.unlock()
        continuation?.resume(throwing: error)
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
