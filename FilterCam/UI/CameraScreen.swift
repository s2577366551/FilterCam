import SwiftUI
import UIKit

@MainActor
struct CameraScreen: View {
    @StateObject private var viewModel: CameraViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var pinchStartZoom: CGFloat?
    @State private var isZoomDialVisible = false
    @State private var zoomDialTask: Task<Void, Never>?
    @State private var pipDragStart: CGPoint?

    init() {
        _viewModel = StateObject(
            wrappedValue: CameraViewModel(previewRenderer: AppEnvironment.makeRenderer())
        )
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            if let renderer = viewModel.previewRenderer {
                CameraPreviewView(renderer: renderer)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
            }

            // 底部压一层渐变，保证白色标签在明亮画面上也看得清。
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.62),
                    .init(color: .black.opacity(0.50), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            focusLayer

            pipDragLayer

            VStack(spacing: 0) {
                TopBar(
                    mode: viewModel.captureMode,
                    flashMode: viewModel.flashMode,
                    isManualFocus: viewModel.isManualFocusEnabled,
                    resolutionBadge: viewModel.photoResolution.badge,
                    isLivePhoto: viewModel.isLivePhotoEnabled,
                    isDualCamera: viewModel.isDualCameraEnabled,
                    isDualSupported: DualCameraService.isSupported,
                    isRecording: viewModel.isRecording,
                    onFlash: { viewModel.toggleFlash() },
                    onManualFocus: { viewModel.toggleManualFocus() },
                    onResolution: { viewModel.togglePhotoResolution() },
                    onLivePhoto: { viewModel.toggleLivePhoto() },
                    onDual: { hideZoomDial(); viewModel.toggleDualCamera() },
                    onFlip: { hideZoomDial(); viewModel.flipCamera() }
                )
                .padding(.top, 8)

                Spacer()

                bottomControls
                    .overlay(alignment: .bottom) {
                        if isZoomDialVisible {
                            ZoomDial(
                                value: viewModel.zoomFactor,
                                range: viewModel.zoomRange,
                                stops: viewModel.zoomStops,
                                onChange: { value in
                                    zoomDialTask?.cancel()
                                    viewModel.setZoom(value)
                                },
                                onInteractionEnded: {
                                    scheduleZoomDialHide(after: 1.4)
                                }
                            )
                            .frame(height: 200)
                            .padding(.bottom, 44)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                    }
            }

            overlay

            if viewModel.isRecording {
                VStack {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                        Text(CameraViewModel.durationText(viewModel.recordingDuration))
                            .font(.system(size: Theme.Font.caption, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Theme.overlay, in: Capsule())
                    .padding(.top, 58)

                    Spacer()
                }
                .allowsHitTesting(false)
            }

            if viewModel.state == .running && !viewModel.hasReceivedFrame {
                ProgressView("正在启动相机…")
                    .tint(Theme.control)
                    .foregroundStyle(Theme.control)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Theme.overlay, in: Capsule())
            }

            if let toast = viewModel.toast {
                VStack {
                    Spacer()
                    ToastView(text: toast)
                        .padding(.bottom, 210)
                }
                .allowsHitTesting(false)
            }
        }
        .sheet(isPresented: $viewModel.isLibraryPresented) {
            FilterLibraryView(
                store: viewModel.filterStore,
                userLUTs: viewModel.userLUTLibrary,
                thumbnails: viewModel.thumbnails,
                selectedID: viewModel.selectedPreset.id,
                onSelect: { viewModel.selectPreset($0) },
                onLUTChanged: { viewModel.refreshThumbnail(for: $0) }
            )
        }
        .sheet(isPresented: $viewModel.isWatermarkSheetPresented) {
            WatermarkSheet(store: viewModel.watermarkStore)
        }
        .fullScreenCover(isPresented: $viewModel.isPreviewPresented) {
            if let photo = viewModel.lastPhoto {
                PhotoPreviewView(
                    image: photo,
                    shareURL: viewModel.lastPhotoFileURL
                ) {
                    viewModel.isPreviewPresented = false
                }
            }
        }
        .onChange(of: viewModel.isLibraryPresented) { _, presented in
            if presented {
                viewModel.refreshThumbnailsFromCurrentFrame()
            }
        }
        .onAppear { viewModel.onAppear() }
        .onDisappear {
            zoomDialTask?.cancel()
            viewModel.onDisappear()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                viewModel.onAppear()
            case .inactive, .background:
                viewModel.onDisappear()
            @unknown default:
                break
            }
        }
    }

    /// 底部控制区：整块吃掉点击，避免控件之间的空隙穿透到全屏对焦层。
    private var bottomControls: some View {
        VStack(spacing: 0) {
            if viewModel.selectedPreset.id != FilterPreset.original.id {
                AdjustmentPanel(
                    adjustments: viewModel.adjustments,
                    onChange: { viewModel.setAdjustments($0) },
                    onReset: { viewModel.resetAdjustments() }
                )
                .padding(.bottom, 4)

                IntensitySlider(
                    value: viewModel.intensity,
                    onChange: { viewModel.setIntensity($0) }
                )
                .padding(.bottom, 8)
            }

            if viewModel.isManualFocusEnabled {
                ManualFocusSlider(
                    value: viewModel.manualFocus,
                    onChange: { viewModel.setManualFocus($0) }
                )
                .padding(.bottom, 8)
            }

            FilterStrip(
                presets: viewModel.stripPresets,
                thumbnails: viewModel.thumbnails,
                selectedID: viewModel.selectedPreset.id,
                onSelect: { viewModel.selectPreset($0) },
                onOpenLibrary: { viewModel.isLibraryPresented = true }
            )
            .padding(.bottom, 4)

            HStack(alignment: .center) {
                lastPhotoButton
                Spacer()
                ShutterButton(
                    isBusy: viewModel.isShutterBusy,
                    isVideoMode: viewModel.captureMode == .video,
                    isRecording: viewModel.isRecording
                ) {
                    if viewModel.captureMode == .video {
                        viewModel.toggleRecording()
                    } else {
                        viewModel.capture()
                    }
                }
                Spacer()
                watermarkButton
            }
            .padding(.horizontal, 24)

            zoomPill

            modePicker
                .padding(.top, 4)
        }
        .padding(.bottom, 6)
        .background(
            Rectangle()
                .fill(Color.black.opacity(0.001))
                .contentShape(Rectangle())
                .onTapGesture { }
        )
    }

    /// 变焦档位：点数字直接切，长按打开弧形变焦盘。
    private var zoomPill: some View {
        HStack(spacing: 0) {
            ForEach(viewModel.zoomPillStops) { stop in
                let isActive = nearestStopValue == stop.value
                Text(pillLabel(for: stop, isActive: isActive))
                    .font(.system(size: Theme.Font.caption, weight: .semibold).monospacedDigit())
                    .foregroundStyle(isActive ? Color.yellow : Theme.control)
                    .frame(width: 44, height: 30)
                    .contentShape(Rectangle())
                    .gesture(
                        LongPressGesture(minimumDuration: 0.28)
                            .onEnded { _ in
                                showZoomDial()
                            }
                            .exclusively(
                                before: TapGesture().onEnded {
                                    viewModel.setZoom(stop.value)
                                    Haptics.selection()
                                }
                            )
                    )
            }
        }
        .padding(.horizontal, 6)
        .background(Theme.overlay, in: Capsule())
        .padding(.top, 2)
        .accessibilityLabel("变焦倍数")
    }

    private var nearestStopValue: CGFloat? {
        let current = viewModel.zoomFactor
        return viewModel.zoomPillStops.min {
            abs($0.value - current) < abs($1.value - current)
        }?.value
    }

    private func pillLabel(for stop: ZoomStop, isActive: Bool) -> String {
        guard isActive else { return stop.label }
        let current = viewModel.zoomFactor
        if abs(current - stop.value) < 0.05 {
            return stop.label + "×"
        }
        return String(format: current < 10 ? "%.1f×" : "%.0f×", current)
    }

    /// 右下角：水印设置入口。
    private var watermarkButton: some View {
        Button {
            viewModel.isWatermarkSheetPresented = true
        } label: {
            ZStack {
                Circle()
                    .fill(
                        viewModel.watermarkStore.isEnabled
                            ? Color.yellow
                            : Color.white.opacity(0.12)
                    )
                Image(systemName: "signature")
                    .font(.system(size: Theme.Font.iconBody, weight: .medium))
                    .foregroundStyle(
                        viewModel.watermarkStore.isEnabled ? Color.black : Theme.control
                    )
            }
            .frame(width: 50, height: 50)
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("水印设置")
    }

    /// 照片 / 视频模式切换（苹果相机那种文字切换）。
    private var modePicker: some View {
        HStack(spacing: 8) {
            ForEach(CaptureMode.allCases) { mode in
                Button {
                    viewModel.selectCaptureMode(mode)
                } label: {
                    Text(mode.displayName)
                        .font(.system(size: Theme.Font.body, weight: .semibold))
                        .foregroundStyle(
                            viewModel.captureMode == mode ? Color.yellow : Theme.controlDim
                        )
                        .frame(width: 68, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isRecording)
            }
        }
    }

    /// 左下角：刚拍照片的缩略图，点开全屏预览。
    @ViewBuilder
    private var lastPhotoButton: some View {
        Button {
            guard viewModel.lastPhoto != nil else { return }
            viewModel.isPreviewPresented = true
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.12))

                if let photo = viewModel.lastPhoto {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: Theme.Font.iconCaption))
                        .foregroundStyle(Theme.controlDim)
                }
            }
            .frame(width: 50, height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(viewModel.lastPhoto == nil)
        .contextMenu {
            Button {
                openPhotosApp()
            } label: {
                Label("在相册中打开", systemImage: "photo.on.rectangle")
            }

            if let url = viewModel.lastPhotoFileURL {
                ShareLink(item: url) {
                    Label(
                        url.pathExtension.lowercased() == "mov" ? "分享视频" : "分享原图",
                        systemImage: "square.and.arrow.up"
                    )
                }
            }
        }
        .accessibilityLabel("查看刚拍的照片")
    }

    /// 跳到系统「照片」App（iOS 没有公开接口定位到某一张，只能打开 App）。
    private func openPhotosApp() {
        guard let url = URL(string: "photos-redirect://") else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - 变焦盘

    private func showZoomDial() {
        let range = viewModel.zoomRange
        guard range.upperBound > range.lowerBound + 0.01 else { return }

        zoomDialTask?.cancel()
        withAnimation(.spring(response: 0.26, dampingFraction: 0.86)) {
            isZoomDialVisible = true
        }
        scheduleZoomDialHide(after: 2.2)
    }

    private func scheduleZoomDialHide(after seconds: Double) {
        zoomDialTask?.cancel()
        zoomDialTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                isZoomDialVisible = false
            }
        }
    }

    private func hideZoomDial() {
        zoomDialTask?.cancel()
        guard isZoomDialVisible else { return }
        withAnimation(.easeOut(duration: 0.16)) {
            isZoomDialVisible = false
        }
    }

    /// 覆盖全屏的透明层：点按对焦，并显示对焦框。
    private var focusLayer: some View {
        GeometryReader { geo in
            ZStack {
                Color.clear
                    .contentShape(Rectangle())

                if let reticle = viewModel.focusReticle {
                    FocusReticleView(isLocked: reticle.isLocked)
                        .position(reticle.position)
                        .allowsHitTesting(false)
                }
            }
            .gesture(
                SpatialTapGesture()
                    .onEnded { value in
                        viewModel.focus(at: value.location, in: geo.size)
                    }
            )
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        if pinchStartZoom == nil {
                            pinchStartZoom = viewModel.zoomFactor
                        }
                        viewModel.setZoom((pinchStartZoom ?? 1) * value.magnification)
                        if isZoomDialVisible {
                            zoomDialTask?.cancel()
                        } else {
                            showZoomDial()
                        }
                    }
                    .onEnded { _ in
                        pinchStartZoom = nil
                        scheduleZoomDialHide(after: 1.2)
                    }
            )
        }
        .ignoresSafeArea()
    }

    // MARK: - 双摄小窗拖动

    private var pipDragLayer: some View {
        GeometryReader { geo in
            if viewModel.isDualCameraEnabled,
               let rect = pipViewRect(in: geo.size) {
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if pipDragStart == nil {
                                    pipDragStart = viewModel.pipCenter
                                }
                                let content = viewModel.previewContentSize
                                guard content.width > 0, content.height > 0 else { return }
                                let scale = AspectFill.transform(
                                    contentSize: content,
                                    in: CGRect(origin: .zero, size: geo.size)
                                ).a
                                guard scale > 0 else { return }
                                let start = pipDragStart ?? viewModel.pipCenter
                                viewModel.movePiP(
                                    to: CGPoint(
                                        x: start.x + value.translation.width / scale / content.width,
                                        y: start.y + value.translation.height / scale / content.height
                                    )
                                )
                            }
                            .onEnded { _ in
                                pipDragStart = nil
                            }
                    )
            }
        }
        .ignoresSafeArea()
    }

    /// 小窗在屏幕上的位置：内容坐标 → AspectFill → 屏幕坐标。
    private func pipViewRect(in bounds: CGSize) -> CGRect? {
        let content = viewModel.previewContentSize
        guard content.width > 0, content.height > 0 else { return nil }

        let contentRect = CGRect(origin: .zero, size: content)
        let ciRect = PiPLayout.rect(
            in: contentRect,
            aspect: PiPLayout.aspect,
            center: viewModel.pipCenter
        )
        let displayRect = CGRect(
            x: ciRect.minX,
            y: content.height - ciRect.maxY,
            width: ciRect.width,
            height: ciRect.height
        )
        let transform = AspectFill.transform(
            contentSize: content,
            in: CGRect(origin: .zero, size: bounds)
        )
        return displayRect.applying(transform)
    }

    @ViewBuilder
    private var overlay: some View {
        switch viewModel.state {
        case .permissionDenied:
            PermissionGateView(
                title: "需要相机权限",
                message: "Sx Cam 需要访问相机才能拍摄照片。请在系统设置中允许相机访问。",
                showsSettingsButton: true,
                retry: { viewModel.retry() }
            )
        case .permissionRestricted:
            PermissionGateView(
                title: "相机不可用",
                message: "当前设备限制了相机访问，可能由家长控制或设备管理策略导致。",
                showsSettingsButton: false,
                retry: { viewModel.retry() }
            )
        case .failed(let message):
            PermissionGateView(
                title: "相机启动失败",
                message: message,
                showsSettingsButton: false,
                retry: { viewModel.retry() }
            )
        case .requestingPermission:
            ProgressView("正在请求相机权限…")
                .tint(Theme.control)
                .foregroundStyle(Theme.control)
        case .paused:
            Text("相机已暂停")
                .font(.system(size: Theme.Font.body))
                .foregroundStyle(Theme.controlDim)
                .padding(12)
                .background(Theme.overlay, in: Capsule())
        case .initializing, .running:
            EmptyView()
        }
    }
}
