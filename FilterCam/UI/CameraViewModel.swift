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
    @Published private(set) var toast: String?
    @Published private(set) var hasReceivedFrame = false
    @Published private(set) var focusReticle: FocusReticle?
    @Published private(set) var isManualFocusEnabled = false
    @Published private(set) var manualFocus: Float = 0.5
    @Published private(set) var photoResolution: PhotoResolution = .standard
    @Published private(set) var isLivePhotoEnabled = false
    @Published private(set) var captureMode: CaptureMode = .photo
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

    private let camera: CameraServicing
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

        self.camera = camera
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
        var presets = filterStore.stripIDs.compactMap { resolvePreset(id: $0) }
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
        camera.stop()
    }

    func retry() {
        Task { await start() }
    }

    func toggleFlash() {
        let all = FlashMode.allCases
        let index = all.firstIndex(of: flashMode) ?? 0
        flashMode = all[(index + 1) % all.count]
        camera.setFlashMode(flashMode)
    }

    func togglePhotoResolution() {
        photoResolution = photoResolution == .standard ? .high : .standard
        camera.setPhotoResolution(photoResolution)
        showToast("拍照画质：\(photoResolution.displayName)")
        Haptics.selection()
    }

    func toggleLivePhoto() {
        let wantOn = !isLivePhotoEnabled
        Task {
            let enabled = await camera.setLivePhotoEnabled(wantOn)
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
        Task {
            do {
                try await camera.switchCamera()
                isFrontCamera.toggle()
                isManualFocusEnabled = false
                focusReticle = nil
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

    // MARK: - 照片 / 视频模式

    func selectCaptureMode(_ mode: CaptureMode) {
        guard mode != captureMode, !isRecording, !isCapturing, !isProcessingVideo else { return }
        guard state == .running else { return }
        Task { await applyCaptureMode(mode) }
    }

    private func applyCaptureMode(_ mode: CaptureMode) async {
        // 视频模式没有实况，先关掉再切，避免拍照格式被改回去。
        if mode == .video, isLivePhotoEnabled {
            _ = await camera.setLivePhotoEnabled(false)
            isLivePhotoEnabled = false
        }
        if mode == .video {
            await requestMicrophoneIfNeeded()
        }
        do {
            try await camera.setCaptureMode(mode)
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
                try await camera.startRecording()
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
                let video = try await camera.stopRecording()
                isRecording = false
                showToast("正在保存视频…")

                let pipeline = filterPipeline
                let info = try await photoSaver.saveVideo(
                    at: video.url,
                    watermark: watermark
                ) { image in
                    pipeline.process(
                        image,
                        preset: settings.preset,
                        intensity: settings.intensity,
                        adjustments: settings.adjustments
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
        guard !isManualFocusEnabled else { return }
        guard let devicePoint = devicePoint(from: viewPoint, in: bounds) else { return }
        showReticle(at: viewPoint, locked: false)
        Haptics.selection()
        Task { try? await camera.focus(at: devicePoint) }
    }

    func toggleManualFocus() {
        isManualFocusEnabled.toggle()
        focusReticle = nil
        if isManualFocusEnabled {
            let value = manualFocus
            Task { try? await camera.setManualFocus(value) }
        } else {
            Task { try? await camera.resumeAutoFocus() }
        }
        Haptics.selection()
    }

    func setManualFocus(_ value: Float) {
        manualFocus = min(max(value, 0), 1)
        guard isManualFocusEnabled else { return }
        let target = manualFocus
        Task { try? await camera.setManualFocus(target) }
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
        let u = isFrontCamera ? nx : 1 - nx
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
                let captured = try await camera.capturePhoto()
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
        camera.onFrame = { [weak self] image in
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
        camera.onStateChange = { [weak self] runtime in
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
            try await camera.start()
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
