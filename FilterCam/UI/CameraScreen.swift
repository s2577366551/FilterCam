import SwiftUI

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
                    .ignoresSafeArea()
            }

            VStack(spacing: 0) {
                TopBar(
                    flashMode: viewModel.flashMode,
                    onFlash: { viewModel.toggleFlash() },
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

                ShutterButton { viewModel.capture() }
                    .padding(.bottom, 12)

                FilterStrip(
                    presets: viewModel.stripPresets,
                    thumbnails: viewModel.thumbnails,
                    selectedID: viewModel.selectedPreset.id,
                    onSelect: { viewModel.selectPreset($0) },
                    onOpenLibrary: { viewModel.isLibraryPresented = true }
                )
                .padding(.bottom, 8)
            }

            overlay

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
                onSelect: { viewModel.selectPreset($0) }
            )
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

    @ViewBuilder
    private var overlay: some View {
        switch viewModel.state {
        case .permissionDenied:
            PermissionGateView(
                title: "需要相机权限",
                message: "FilterCam 需要访问相机才能拍摄照片。请在系统设置中允许相机访问。",
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
