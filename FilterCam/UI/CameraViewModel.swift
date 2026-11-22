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
    @Published private(set) var isSavingPhoto = false
    @Published private(set) var focusReticle: FocusReticle?
    @Published private(set) var isManualFocusEnabled = false
    @Published private(set) var manualFocus: Float = 0.5
    @Published private(set) var photoResolution: PhotoResolution = .standard
    @Published private(set) var previewContentSize: CGSize = .zero

    let previewRenderer: PreviewRenderer?
    let filterStore: FilterStore
    let userLUTLibrary: UserLUTLibrary

    private let camera: CameraServicing
    private let permission: CameraPermissionProviding
    private let filterPipeline: FilterPipeline
    private let thumbnailService: ThumbnailService
    private let photoSaver: PhotoLibrarySaver
    private let settingsLock = NSLock()
    private var settingsPreset: FilterPreset = .original
    private var settingsIntensity: Float = 0
    private var settingsAdjustments: FilterAdjustments = .neutral
    private var didCaptureThumbnailSource = false
    private var didReceiveFrame = false
    private var frameSize: CGSize = .zero
    private var reticleTask: Task<Void, Never>?
    private var adjustmentsByPreset: [String: FilterAdjustments] = [:]
    private var lastFrame: CIImage?

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
        self.filterStore = FilterStore()
        self.userLUTLibrary = library

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

    func flipCamera() {
        Task {
            do {
                try await camera.switchCamera()
                isFrontCamera.toggle()
                isManualFocusEnabled = false
                focusReticle = nil
                settingsLock.lock()
                didCaptureThumbnailSource = false
                settingsLock.unlock()
                thumbnails.removeAll()
            } catch {
                Log.camera.error("切换摄像头失败: \(error.localizedDescription)")
            }
        }
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
        guard !isSavingPhoto else { return }
        isSavingPhoto = true
        Task {
            defer { isSavingPhoto = false }
            do {
                let captured = try await camera.capturePhoto()
                Haptics.shutter()

                let settings = currentSettings()
                let pipeline = filterPipeline
                let info = try await photoSaver.save(captured) { image in
                    pipeline.process(
                        image,
                        preset: settings.preset,
                        intensity: settings.intensity,
                        adjustments: settings.adjustments
                    )
                }
                showToast("已保存 \(info.pixelWidth)×\(info.pixelHeight)")
            } catch {
                showToast(error.localizedDescription)
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
                self.frameSize = previewSource.extent.size
            }
            let size = self.frameSize
            self.settingsLock.unlock()
            if isFirstFrame {
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
        let shouldCapture = !didCaptureThumbnailSource
        if shouldCapture {
            didCaptureThumbnailSource = true
        }
        settingsLock.unlock()
        guard shouldCapture else { return }

        thumbnailService.generate(from: image, presets: PresetCatalog.all) { [weak self] images in
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
