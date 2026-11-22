import SwiftUI
import UIKit

@MainActor
struct CameraScreen: View {
    @StateObject private var viewModel: CameraViewModel
    @Environment(\.scenePhase) private var scenePhase

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

            VStack(spacing: 0) {
                TopBar(
                    mode: viewModel.captureMode,
                    flashMode: viewModel.flashMode,
                    isManualFocus: viewModel.isManualFocusEnabled,
                    resolutionBadge: viewModel.photoResolution.badge,
                    isLivePhoto: viewModel.isLivePhotoEnabled,
                    isWatermarkEnabled: viewModel.watermarkStore.isEnabled,
                    isRecording: viewModel.isRecording,
                    onFlash: { viewModel.toggleFlash() },
                    onManualFocus: { viewModel.toggleManualFocus() },
                    onResolution: { viewModel.togglePhotoResolution() },
                    onLivePhoto: { viewModel.toggleLivePhoto() },
                    onWatermark: { viewModel.isWatermarkSheetPresented = true },
                    onFlip: { viewModel.flipCamera() }
                )
                .padding(.top, 8)

                Spacer()

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
                    Color.clear
                        .frame(width: 50, height: 50)
                }
                .padding(.horizontal, 24)

                modePicker
                    .padding(.top, 4)
                    .padding(.bottom, 6)
            }

            overlay

            if viewModel.isRecording {
                VStack {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                        Text(CameraViewModel.durationText(viewModel.recordingDuration))
                            .font(.system(size: 13, weight: .semibold).monospacedDigit())
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
        .onDisappear { viewModel.onDisappear() }
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

    /// 照片 / 视频模式切换（苹果相机那种文字切换）。
    private var modePicker: some View {
        HStack(spacing: 26) {
            ForEach(CaptureMode.allCases) { mode in
                Button {
                    viewModel.selectCaptureMode(mode)
                } label: {
                    Text(mode.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(
                            viewModel.captureMode == mode ? Color.yellow : Theme.controlDim
                        )
                        .frame(minWidth: 44, minHeight: 28)
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
                        .font(.system(size: 15))
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
        }
        .ignoresSafeArea()
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
                .font(.system(size: 15))
                .foregroundStyle(Theme.controlDim)
                .padding(12)
                .background(Theme.overlay, in: Capsule())
        case .initializing, .running:
            EmptyView()
        }
    }
}
