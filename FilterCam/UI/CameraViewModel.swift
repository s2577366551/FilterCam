import AVFoundation
import Combine
import CoreImage
import SwiftUI
import UIKit

@MainActor
final class CameraViewModel: ObservableObject {
    enum State: Equatable {
        case initializing
        case requestingPermission
        case permissionDenied
        case permissionRestricted
        case running
        case paused
        case failed(String)
    }

    @Published private(set) var state: State = .initializing
    @Published private(set) var flashMode: FlashMode = .auto
    @Published private(set) var isFrontCamera = false
    @Published private(set) var selectedPreset: FilterPreset = .original
    @Published private(set) var intensity: Float = 1
    @Published private(set) var adjustments: FilterAdjustments = .neutral
    @Published private(set) var thumbnails: [String: UIImage] = [:]
    @Published var isLibraryPresented = false
    @Published var isFilterSheetPresented = false
    @Published var isAdjustSheetPresented = false
    @Published private(set) var toast: String?
    @Published private(set) var hasReceivedFrame = false
    @Published private(set) var focusReticle: FocusReticle?
    @Published private(set) var isManualFocusEnabled = false
    @Published private(set) var manualFocus: Float = 0.5
    @Published private(set) var zoomFactor: CGFloat = 1
    @Published private(set) var photoResolution: PhotoResolution = .standard
    @Published private(set) var isLivePhotoEnabled = false
    @Published private(set) var captureMode: CaptureMode = .photo
    @Published private(set) var isDualCameraEnabled = false
    /// 双摄时是否前摄为大画面（后摄变小窗）。
    @Published private(set) var isDualFrontMain = false
    @Published private(set) var pipCenter = PiPLayout.defaultCenter
    @Published private(set) var isRecording = false
    @Published private(set) var recordingDuration: TimeInterval = 0
    @Published var isWatermarkSheetPresented = false
    @Published private(set) var lastPhoto: UIImage?
    @Published private(set) var lastPhotoFileURL: URL?
    @Published var isPreviewPresented = false
    @Published private(set) var isCapturing = false
    @Published private(set) var isProcessingVideo = false
    @Published private(set) var pendingSaveCount = 0

    /// 快门是否该显示忙碌：正在触发快门、正在导出视频，或排队保存的照片太多。
    var isShutterBusy: Bool {
        isCapturing || isProcessingVideo || pendingSaveCount >= maxPendingSaves
    }

    /// 最高画质单张占用内存大，排队数量要收窄。
    private var maxPendingSaves: Int {
        photoResolution == .high ? 1 : 2
    }
    @Published private(set) var previewContentSize: CGSize = .zero

    let previewRenderer: PreviewRenderer?
    let filterStore: FilterStore
    let userLUTLibrary: UserLUTLibrary
    let watermarkStore = WatermarkStore.shared

    private var singleCamera: CameraServicing
    private var activeCamera: CameraServicing
    private let permission: CameraPermissionProviding
    private let filterPipeline: FilterPipeline
    private let thumbnailService: ThumbnailService
    private let photoSaver: PhotoLibrarySaver
    private let renderContext: CIContext
    private let settingsLock = NSLock()
    private var settingsPreset: FilterPreset = .original
    private var settingsIntensity: Float = 0
    private var settingsAdjustments: FilterAdjustments = .neutral
    private var didCaptureThumbnailSource = false
    private var frameCount = 0
    private var didReceiveFrame = false
    private var frameSize: CGSize = .zero
    private var reticleTask: Task<Void, Never>?
    private var recordingTimer: Task<Void, Never>?
    private var saveChain: Task<Void, Never>?
    private var adjustmentsByPreset: [String: FilterAdjustments] = [:]
    private var lastFrame: CIImage?
    private var watermarkCancellable: AnyCancellable?

    init(
        camera: CameraServicing = CameraService(),
        permission: CameraPermissionProviding = SystemCameraPermission(),
        previewRenderer: PreviewRenderer?
    ) {
        let context = CIContext(options: [
            .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any
        ])
        let library = UserLUTLibrary.shared
        let pipeline = CoreImagePipeline(
            lutResolver: CompositeLUTResolver(bundled: LUTLoader(), user: library),
            context: context
        )

        self.singleCamera = camera
        self.activeCamera = camera
        self.permission = permission
        self.previewRenderer = previewRenderer
        self.filterPipeline = pipeline
        self.thumbnailService = ThumbnailService(pipeline: pipeline, context: context)
        self.photoSaver = PhotoLibrarySaver(context: context)
        self.renderContext = context
        self.filterStore = FilterStore()
        self.userLUTLibrary = library

        // 水印设置变化时刷新界面（顶栏的开关状态）。
        watermarkCancellable = watermarkStore.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }

        bindCamera()
    }

    var stripPresets: [FilterPreset] {
        var seen = Set<String>()
        var presets = filterStore.stripIDs
            .compactMap { resolvePreset(id: $0) }
            .filter { seen.insert($0.id).inserted }
        if !presets.contains(selectedPreset) {
            presets = [selectedPreset] + presets.prefix(FilterStore.stripLimit)
        }
        return presets
    }

    func onAppear() {
        guard previewRenderer != nil else {
            state = .failed("设备不支持 Metal 渲染")
            return
        }
        Task { await start() }
    }

    func onDisappear() {
        if isRecording {
            stopRecordingTimer()
            isRecording = false
        }
        Task { await activeCamera.stop() }
    }

    func retry() {
        Task {
            if isRecording {
                stopRecordingTimer()
                isRecording = false
            }
            state = .initializing
            // 运行时错误后旧会话可能已经不可用，重建一个再启动。
            let old = activeCamera
            old.onFrame = nil
            old.onStateChange = nil
            await old.stop()

            let camera = CameraService()
            singleCamera = camera
            if isDualCameraEnabled {
                activeCamera = DualCameraService()
                isDualFrontMain = false
            } else {
                activeCamera = camera
            }
            resetFrameState()
            bindCamera()
            await start()
        }
    }

    func toggleFlash() {
        let all = FlashMode.allCases
        let index = all.firstIndex(of: flashMode) ?? 0
        flashMode = all[(index + 1) % all.count]
        activeCamera.setFlashMode(flashMode)
    }

    func togglePhotoResolution() {
        guard !isDualCameraEnabled else {
            showToast("双摄固定 12MP")
            return
        }
        photoResolution = photoResolution == .standard ? .high : .standard
        activeCamera.setPhotoResolution(photoResolution)
        showToast("拍照画质：\(photoResolution.displayName)")
        Haptics.selection()
    }

    func toggleLivePhoto() {
        guard !isDualCameraEnabled else {
            showToast("双摄模式下不支持实况照片")
            return
        }
        let wantOn = !isLivePhotoEnabled
        Task {
            let enabled = await activeCamera.setLivePhotoEnabled(wantOn)
            isLivePhotoEnabled = enabled
            if wantOn {
                showToast(enabled ? "实况照片已开启" : "这台设备不支持实况照片")
            } else {
                showToast("实况照片已关闭")
            }
            Haptics.selection()
        }
    }

    func flipCamera() {
        guard !isRecording else {
            showToast("录制中不能切换摄像头")
            return
        }
        guard !isDualCameraEnabled else {
            showToast("双摄模式下前后摄像头已同时开启")
            return
        }
        Task {
            do {
                try await activeCamera.switchCamera()
                isFrontCamera.toggle()
                isManualFocusEnabled = false
                focusReticle = nil
                zoomFactor = 1
                settingsLock.lock()
                didCaptureThumbnailSource = false
                frameCount = 0
                settingsLock.unlock()
                thumbnails.removeAll()
            } catch {
                Log.camera.error("切换摄像头失败: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - 前后双摄

    func toggleDualCamera() {
        guard DualCameraService.isSupported else {
            showToast("这台设备不支持前后双摄")
            return
        }
        guard !isRecording, !isCapturing, !isProcessingVideo else { return }
        let turningOn = !isDualCameraEnabled

        Task {
            CrashLogger.breadcrumb("切换双摄: \(turningOn ? "开启" : "关闭")")
            activeCamera.onFrame = nil
            activeCamera.onStateChange = nil
            await activeCamera.stop()
            CrashLogger.breadcrumb("切换双摄: 旧会话已停止")
            if turningOn {
                if isLivePhotoEnabled {
                    _ = await activeCamera.setLivePhotoEnabled(false)
                    isLivePhotoEnabled = false
                }
                photoResolution = .standard
                isManualFocusEnabled = false
                isDualFrontMain = false
                activeCamera = DualCameraService()
                isDualCameraEnabled = true
                movePiP(to: PiPLayout.defaultCenter)
            } else {
                activeCamera = singleCamera
                isDualCameraEnabled = false
                isDualFrontMain = false
            }

            resetFrameState()
            bindCamera()
            CrashLogger.breadcrumb("切换双摄: 准备启动新会话")
            do {
                try await activeCamera.start()
                activeCamera.setFlashMode(flashMode)
                activeCamera.setPhotoResolution(photoResolution)
                zoomFactor = 1
                activeCamera.setZoomFactor(1)
                if captureMode == .video {
                    try? await activeCamera.setCaptureMode(.video)
                }
                showToast(turningOn ? "前后双摄已开启" : "已关闭前后双摄")
            } catch {
                CrashLogger.breadcrumb("切换双摄失败: \(error.localizedDescription)")
                showToast(error.localizedDescription)
            }
            Haptics.selection()
        }
    }

    /// 点小窗：前后画面互换，前摄变大画面、后摄变小窗（再点换回来）。
    func swapDualCameras() {
        guard isDualCameraEnabled else { return }
        guard let dual = activeCamera as? DualCameraService else { return }
        dual.swapDualLayout()
        isDualFrontMain.toggle()
        // 换主摄像头后变焦要重新来，避免把后摄的倍率套到前摄上。
        zoomFactor = 1
        dual.setZoomFactor(1)
        Haptics.selection()
        showToast(isDualFrontMain ? "前置为主画面" : "后置为主画面")
    }

    /// 拖动前后双摄的小窗。center 是显示坐标系的归一化位置（原点左上）。
    func movePiP(to center: CGPoint) {
        var x = min(max(center.x, 0), 1)
        var y = min(max(center.y, 0), 1)

        let content = previewContentSize
        if content.width > 0, content.height > 0 {
            let ratio = content.width / content.height
            let width = PiPLayout.widthRatio
            let height = width * ratio / PiPLayout.aspect
            let marginX: CGFloat = 0.035
            let marginY = marginX * ratio
            let minX = marginX + width / 2
            let maxX = 1 - marginX - width / 2
            let minY = marginY + height / 2
            let maxY = 1 - marginY - height / 2
            x = min(max(x, minX), max(minX, maxX))
            y = min(max(y, minY), max(minY, maxY))
        }

        pipCenter = CGPoint(x: x, y: y)
        (activeCamera as? DualCameraService)?.setPiPCenter(pipCenter)
    }

    private func resetFrameState() {
        settingsLock.lock()
        didCaptureThumbnailSource = false
        frameCount = 0
        didReceiveFrame = false
        frameSize = .zero
        lastFrame = nil
        settingsLock.unlock()
        thumbnails.removeAll()
        hasReceivedFrame = false
        previewContentSize = .zero
    }

    // MARK: - 照片 / 视频模式

    func selectCaptureMode(_ mode: CaptureMode) {
        guard mode != captureMode, !isRecording, !isCapturing, !isProcessingVideo else { return }
        guard state == .running else { return }
        Task { await applyCaptureMode(mode) }
    }

    private func applyCaptureMode(_ mode: CaptureMode) async {
        // 视频模式没有实况，先关掉再切，避免拍照格式被改回去。
        if mode == .video, isLivePhotoEnabled {
            _ = await activeCamera.setLivePhotoEnabled(false)
            isLivePhotoEnabled = false
        }
        if mode == .video {
            await requestMicrophoneIfNeeded()
        }
        do {
            try await activeCamera.setCaptureMode(mode)
            captureMode = mode
            settingsLock.lock()
            didCaptureThumbnailSource = false
            frameCount = 0
            settingsLock.unlock()
            Haptics.selection()
        } catch {
            showToast(error.localizedDescription)
        }
    }

    private func requestMicrophoneIfNeeded() async {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined else { return }
        _ = await AVCaptureDevice.requestAccess(for: .audio)
    }

    func toggleRecording() {
        if isRecording {
            finishRecording()
        } else {
            beginRecording()
        }
    }

    private func beginRecording() {
        guard !isRecording else { return }
        isRecording = true
        recordingDuration = 0
        startRecordingTimer()
        Haptics.shutter()
        Task {
            do {
                try await activeCamera.startRecording()
            } catch {
                isRecording = false
                stopRecordingTimer()
                showToast(error.localizedDescription)
            }
        }
    }

    private func finishRecording() {
        guard isRecording, !isProcessingVideo else { return }
        stopRecordingTimer()
        isRecording = false
        let fallbackDuration = recordingDuration
        let settings = currentSettings()
        let watermark = watermarkStore.effectiveText
        isProcessingVideo = true
        pendingSaveCount += 1

        Task {
            defer {
                pendingSaveCount = max(0, pendingSaveCount - 1)
                isProcessingVideo = false
            }
            do {
                let video = try await activeCamera.stopRecording()
                isRecording = false
                showToast("正在保存视频…")

                let pipeline = filterPipeline
                let transform: (CIImage) -> CIImage = { image in
                    pipeline.process(
                        image,
                        preset: settings.preset,
                        intensity: settings.intensity,
                        adjustments: settings.adjustments
                    )
                }
                let info: SavedVideo
                if let frontURL = video.frontURL {
                    info = try await photoSaver.saveDualVideo(
                        backURL: video.url,
                        frontURL: frontURL,
                        pipCenter: pipCenter,
                        watermark: watermark,
                        applying: transform
                    )
                } else {
                    info = try await photoSaver.saveVideo(
                        at: video.url,
                        watermark: watermark,
                        applying: transform
                    )
                }

                lastPhoto = Self.makeVideoThumbnail(at: info.fileURL)
                if let previous = lastPhotoFileURL {
                    try? FileManager.default.removeItem(at: previous)
                }
                lastPhotoFileURL = info.fileURL
                let duration = info.duration > 0 ? info.duration : fallbackDuration
                showToast("已保存视频 \(Self.durationText(duration))")
            } catch {
                isRecording = false
                showToast(error.localizedDescription)
            }
        }
    }

    private func startRecordingTimer() {
        stopRecordingTimer()
        let start = Date()
        recordingTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard let self, !Task.isCancelled else { return }
                self.recordingDuration = Date().timeIntervalSince(start)
            }
        }
    }

    private func stopRecordingTimer() {
        recordingTimer?.cancel()
        recordingTimer = nil
    }

    static func durationText(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private static func makeVideoThumbnail(at url: URL?) -> UIImage? {
        guard let url else { return nil }
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1024, height: 1024)
        let time = CMTime(value: 1, timescale: 10)
        guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    // MARK: - 对焦

    /// 点击画面：在该点自动对焦并自动曝光。
    func focus(at viewPoint: CGPoint, in bounds: CGSize) {
        // MF 模式下也允许点按对焦：点哪里就先自动对到哪里，
        // 之后还能用 MF 滑杆手动微调。
        guard let devicePoint = devicePoint(from: viewPoint, in: bounds) else { return }
        showReticle(at: viewPoint, locked: false)
        Haptics.selection()
        Task { try? await activeCamera.focus(at: devicePoint) }
    }

    func toggleManualFocus() {
        isManualFocusEnabled.toggle()
        focusReticle = nil
        if isManualFocusEnabled {
            let value = manualFocus
            Task { try? await activeCamera.setManualFocus(value) }
        } else {
            Task { try? await activeCamera.resumeAutoFocus() }
        }
        Haptics.selection()
    }

    func setManualFocus(_ value: Float) {
        manualFocus = min(max(value, 0), 1)
        guard isManualFocusEnabled else { return }
        let target = manualFocus
        Task { try? await activeCamera.setManualFocus(target) }
    }

    // MARK: - 变焦

    var zoomRange: ClosedRange<CGFloat> {
        let range = activeCamera.zoomRange
        let low = max(range.lowerBound, isRecording ? 1 : 0.5)
        return low...max(range.upperBound, low)
    }

    /// 苹果相机那种档位：0.5 / 1 / 2 / 3 / 最大，按设备实际能力裁剪。
    var zoomStops: [ZoomStop] {
        let range = zoomRange
        let hasUltraWide = range.lowerBound <= 0.55
        var stops: [ZoomStop] = []

        if hasUltraWide {
            stops.append(ZoomStop(value: 0.5, label: "0.5", millimeters: "13 MM"))
        }
        for value in [1.0, 2.0, 3.0] as [CGFloat] where range.contains(value) {
            let mm: String?
            switch value {
            case 1: mm = hasUltraWide ? "24 MM" : nil
            case 2: mm = hasUltraWide ? "48 MM" : nil
            default: mm = nil
            }
            stops.append(ZoomStop(
                value: value,
                label: value == 1 ? "1" : String(format: "%.0f", value),
                millimeters: mm
            ))
        }

        let maxValue = min(range.upperBound, 15)
        if maxValue > 3.5 {
            stops.append(ZoomStop(
                value: maxValue,
                label: String(format: "%.0f", maxValue),
                millimeters: nil
            ))
        }
        return stops
    }

    /// 底部胶囊只放常用档位，最远倍数留给变焦盘。
    var zoomPillStops: [ZoomStop] {
        let optical = zoomStops.filter { $0.value <= 3.5 }
        return optical.isEmpty ? Array(zoomStops.prefix(1)) : optical
    }

    func setZoom(_ factor: CGFloat) {
        let range = zoomRange
        let clamped = min(max(factor, range.lowerBound), range.upperBound)
        guard abs(clamped - zoomFactor) > 0.005 else { return }

        // 超广角镜头只有 12MP，48MP 档自动退回标准。
        if clamped < 0.95, photoResolution == .high {
            photoResolution = .standard
            activeCamera.setPhotoResolution(.standard)
            showToast("超广角最高 12MP，已切回标准")
        }

        zoomFactor = clamped
        activeCamera.setZoomFactor(clamped)
    }

    func resetZoom() {
        guard abs(zoomFactor - 1) > 0.01 else { return }
        zoomFactor = 1
        activeCamera.setZoomFactor(1)
        Haptics.selection()
    }

    private func showReticle(at point: CGPoint, locked: Bool) {
        reticleTask?.cancel()
        withAnimation(.easeOut(duration: 0.12)) {
            focusReticle = FocusReticle(position: point, isLocked: locked)
        }
        guard !locked else { return }
        reticleTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.25)) {
                self?.focusReticle = nil
            }
        }
    }

    /// 屏幕点击坐标 → 相机设备坐标（0...1）。预览是 AspectFill 裁切，需要反算。
    private func devicePoint(from viewPoint: CGPoint, in bounds: CGSize) -> CGPoint? {
        let content = previewContentSize
        guard content.width > 0, content.height > 0,
              bounds.width > 0, bounds.height > 0 else { return nil }

        let transform = AspectFill.transform(
            contentSize: content,
            in: CGRect(origin: .zero, size: bounds)
        )
        let inContent = viewPoint.applying(transform.inverted())
        let nx = min(max(inContent.x / content.width, 0), 1)
        let ny = min(max(inContent.y / content.height, 0), 1)

        // 预览由传感器画面顺时针旋转 90° 得到；前置摄像头额外做了水平镜像。
        let usingFront = isFrontCamera || isDualFrontMain
        let u = usingFront ? nx : 1 - nx
        return CGPoint(x: ny, y: u)
    }

    func selectPreset(_ preset: FilterPreset) {
        adjustmentsByPreset[selectedPreset.id] = adjustments
        selectedPreset = preset
        adjustments = adjustmentsByPreset[preset.id] ?? .neutral
        if preset.id != FilterPreset.original.id && intensity == 0 {
            intensity = 1
        }
        applySettings()
        filterStore.markUsed(preset.id)
        Haptics.selection()
        generateThumbnailIfNeeded(for: preset)
    }

    func setIntensity(_ value: Float) {
        intensity = min(max(value, 0), 1)
        applySettings()
    }

    func setAdjustments(_ value: FilterAdjustments) {
        adjustments = value.clamped()
        applySettings()
    }

    func resetAdjustments() {
        setAdjustments(.neutral)
    }

    func capture() {
        guard !isCapturing, pendingSaveCount < maxPendingSaves else { return }
        isCapturing = true
        let watermark = watermarkStore.effectiveText
        Task {
            defer { isCapturing = false }
            do {
                let captured = try await activeCamera.capturePhoto()
                Haptics.shutter()

                let settings = currentSettings()
                // 立刻出缩略图，让用户马上看到拍到了什么。
                lastPhoto = makePreviewImage(from: captured, settings: settings)
                enqueueSave(captured, settings: settings, watermark: watermark)
            } catch {
                showToast(error.localizedDescription)
            }
        }
    }

    /// 保存排队执行：快门不必等编码和写相册完成，可以继续拍。
    private func enqueueSave(
        _ captured: CapturedPhoto,
        settings: (preset: FilterPreset, intensity: Float, adjustments: FilterAdjustments),
        watermark: String?
    ) {
        pendingSaveCount += 1
        let previous = saveChain
        saveChain = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            await self.performSave(captured, settings: settings, watermark: watermark)
            self.pendingSaveCount = max(0, self.pendingSaveCount - 1)
        }
    }

    private func performSave(
        _ captured: CapturedPhoto,
        settings: (preset: FilterPreset, intensity: Float, adjustments: FilterAdjustments),
        watermark: String?
    ) async {
        do {
            let pipeline = filterPipeline
            let info = try await photoSaver.save(
                captured,
                watermark: watermark
            ) { image in
                pipeline.process(
                    image,
                    preset: settings.preset,
                    intensity: settings.intensity,
                    adjustments: settings.adjustments
                )
            }
            if let previous = lastPhotoFileURL {
                try? FileManager.default.removeItem(at: previous)
            }
            lastPhotoFileURL = info.fileURL
            showToast(
                "已保存 \(info.pixelWidth)×\(info.pixelHeight)"
                    + (info.isLivePhoto ? " 实况" : "")
            )
        } catch {
            showToast(error.localizedDescription)
        }
    }

    /// LUT 输入类型改变后，重新生成对应滤镜的缩略图。
    func refreshThumbnail(for presetID: String) {
        guard let frame = lastFrame,
              let preset = resolvePreset(id: presetID) else { return }
        thumbnailService.generate(from: frame, presets: [preset]) { [weak self] images in
            Task { @MainActor in
                self?.thumbnails.merge(images) { _, new in new }
            }
        }
    }

    private func bindCamera() {
        activeCamera.onFrame = { [weak self] image in
            guard let self else { return }
            // .photo 预设下视频帧是传感器全尺寸（约 4032×3024）。
            // 预览只需要够清楚的尺寸，先降采样再走滤镜，避免每帧处理千万像素。
            let previewSource = Self.downscaledForPreview(image)
            let settings = self.currentSettings()
            let output = self.filterPipeline.process(
                previewSource,
                preset: settings.preset,
                intensity: settings.intensity,
                adjustments: settings.adjustments
            )
            self.previewRenderer?.submit(output)
            self.settingsLock.lock()
            self.lastFrame = previewSource
            let isFirstFrame = !self.didReceiveFrame
            if isFirstFrame {
                self.didReceiveFrame = true
            }
            let previousSize = self.frameSize
            self.frameSize = previewSource.extent.size
            let size = self.frameSize
            self.settingsLock.unlock()
            if isFirstFrame || size != previousSize {
                DispatchQueue.main.async {
                    self.hasReceivedFrame = true
                    self.previewContentSize = size
                }
            }
            self.captureThumbnailSource(from: previewSource)
        }
        activeCamera.onStateChange = { [weak self] runtime in
            Task { @MainActor in
                self?.apply(runtime)
            }
        }
    }

    private func apply(_ runtime: CameraRuntimeState) {
        switch runtime {
        case .idle:
            break
        case .running:
            if state != .permissionDenied && state != .permissionRestricted {
                state = .running
            }
        case .interrupted:
            state = .paused
        case .failed(let error):
            state = .failed(error.localizedDescription)
        }
    }

    private func start() async {
        switch permission.status {
        case .authorized:
            await runSession()
        case .notDetermined:
            state = .requestingPermission
            let result = await permission.request()
            switch result {
            case .authorized:
                await runSession()
            case .restricted:
                state = .permissionRestricted
            default:
                state = .permissionDenied
            }
        case .denied:
            state = .permissionDenied
        case .restricted:
            state = .permissionRestricted
        }
    }

    private func runSession() async {
        do {
            try await activeCamera.start()
            activeCamera.setZoomFactor(zoomFactor)
            state = .running
        } catch let error as CameraError {
            switch error {
            case .permissionDenied:
                state = .permissionDenied
            case .permissionRestricted:
                state = .permissionRestricted
            default:
                state = .failed(error.localizedDescription)
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func applySettings() {
        settingsLock.lock()
        settingsPreset = selectedPreset
        settingsIntensity = selectedPreset.id == FilterPreset.original.id ? 0 : intensity
        settingsAdjustments = adjustments
        settingsLock.unlock()
    }

    private func currentSettings() -> (
        preset: FilterPreset,
        intensity: Float,
        adjustments: FilterAdjustments
    ) {
        settingsLock.lock()
        defer { settingsLock.unlock() }
        return (settingsPreset, settingsIntensity, settingsAdjustments)
    }

    /// 生成用于 App 内预览的缩略图（长边 2048，足够看清又不占内存）。
    private func makePreviewImage(
        from captured: CapturedPhoto,
        settings: (preset: FilterPreset, intensity: Float, adjustments: FilterAdjustments)
    ) -> UIImage? {
        let oriented = captured.image.oriented(captured.orientation)
        let extent = oriented.extent
        let longest = max(extent.width, extent.height)
        guard longest > 0 else { return nil }

        let limit: CGFloat = 2048
        let scale = min(1, limit / longest)
        let scaled = oriented.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let filtered = filterPipeline.process(
            scaled,
            preset: settings.preset,
            intensity: settings.intensity,
            adjustments: settings.adjustments
        )
        guard let cgImage = renderContext.createCGImage(
            filtered,
            from: filtered.extent,
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
        ) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    /// 预览用的降采样：长边超过 1440 就等比缩小。拍照不走这里，保持全分辨率。
    private static func downscaledForPreview(_ image: CIImage) -> CIImage {
        let extent = image.extent
        let longest = max(extent.width, extent.height)
        let limit: CGFloat = 1440
        guard longest > limit, longest > 0 else { return image }
        let scale = limit / longest
        return image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }

    private func captureThumbnailSource(from image: CIImage) {
        settingsLock.lock()
        frameCount += 1
        // 等对焦和曝光稳定（约 1.2 秒 / 36 帧）再取缩略图源，否则会是糊的。
        let shouldCapture = !didCaptureThumbnailSource && frameCount >= 36
        if shouldCapture {
            didCaptureThumbnailSource = true
        }
        settingsLock.unlock()
        guard shouldCapture else { return }

        generateThumbnails(from: image)
    }

    /// 用当前画面重新生成全部缩略图（含导入的 LUT）。
    func refreshThumbnailsFromCurrentFrame() {
        guard let frame = lastFrame else { return }
        generateThumbnails(from: frame)
    }

    private func generateThumbnails(from image: CIImage) {
        let presets = PresetCatalog.all
            + userLUTLibrary.currentLUTs().map { FilterPreset.user($0) }
            + OfficialLUTLibrary.shared.luts.map { FilterPreset.official($0) }
        thumbnailService.generate(from: image, presets: presets) { [weak self] images in
            Task { @MainActor in
                self?.thumbnails.merge(images) { _, new in new }
            }
        }
    }

    private func resolvePreset(id: String) -> FilterPreset? {
        if let preset = PresetCatalog.byID[id] {
            return preset
        }
        if id.hasPrefix("official_") {
            let officialID = String(id.dropFirst("official_".count))
            guard let lut = OfficialLUTLibrary.shared.luts.first(where: { $0.id == officialID }) else {
                return nil
            }
            return .official(lut)
        }
        guard id.hasPrefix("user_") else { return nil }
        let lutID = String(id.dropFirst("user_".count))
        guard let lut = userLUTLibrary.currentLUTs().first(where: { $0.id == lutID }) else {
            return nil
        }
        return .user(lut)
    }

    private func generateThumbnailIfNeeded(for preset: FilterPreset) {
        guard thumbnails[preset.id] == nil else { return }
        settingsLock.lock()
        let frame = lastFrame
        settingsLock.unlock()
        guard let frame else { return }

        thumbnailService.generate(from: frame, presets: [preset]) { [weak self] images in
            Task { @MainActor in
                self?.thumbnails.merge(images) { _, new in new }
            }
        }
    }

    private func showToast(_ text: String) {
        toast = text
        Task {
            try? await Task.sleep(for: .seconds(2))
            if toast == text {
                toast = nil
            }
        }
    }
}
