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

    let previewRenderer: PreviewRenderer?
    let filterStore: FilterStore
    let userLUTLibrary: UserLUTLibrary

    private let camera: CameraServicing
    private let permission: CameraPermissionProviding
    private let filterPipeline: FilterPipeline
    private let thumbnailService: ThumbnailService
    private let settingsLock = NSLock()
    private var settingsPreset: FilterPreset = .original
    private var settingsIntensity: Float = 0
    private var settingsAdjustments: FilterAdjustments = .neutral
    private var didCaptureThumbnailSource = false
    private var didReceiveFrame = false
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

    func flipCamera() {
        Task {
            do {
                try await camera.switchCamera()
                isFrontCamera.toggle()
                settingsLock.lock()
                didCaptureThumbnailSource = false
                settingsLock.unlock()
                thumbnails.removeAll()
            } catch {
                Log.camera.error("切换摄像头失败: \(error.localizedDescription)")
            }
        }
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
        Task {
            do {
                let data = try await camera.capturePhoto()
                Haptics.shutter()
                showToast("已拍摄 \(data.count / 1024) KB（保存将在下一阶段接入）")
            } catch {
                showToast(error.localizedDescription)
            }
        }
    }

    private func bindCamera() {
        camera.onFrame = { [weak self] image in
            guard let self else { return }
            let settings = self.currentSettings()
            let output = self.filterPipeline.process(
                image,
                preset: settings.preset,
                intensity: settings.intensity,
                adjustments: settings.adjustments
            )
            self.previewRenderer?.submit(output)
            self.settingsLock.lock()
            self.lastFrame = image
            let isFirstFrame = !self.didReceiveFrame
            if isFirstFrame {
                self.didReceiveFrame = true
            }
            self.settingsLock.unlock()
            if isFirstFrame {
                DispatchQueue.main.async {
                    self.hasReceivedFrame = true
                }
            }
            self.captureThumbnailSource(from: image)
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
