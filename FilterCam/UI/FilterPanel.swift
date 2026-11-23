import SwiftUI

/// 底部弹出的滤镜面板：缩略图横条 + 强度。
@MainActor
struct FilterPanel: View {
    @ObservedObject var viewModel: CameraViewModel

    private var showsIntensity: Bool {
        viewModel.selectedPreset.id != FilterPreset.original.id
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Text("滤镜")
                    .font(.system(size: Theme.Font.body, weight: .semibold))
                    .foregroundStyle(Theme.control)

                Spacer()

                Text(viewModel.selectedPreset.stripName)
                    .font(.system(size: Theme.Font.caption))
                    .foregroundStyle(Theme.controlDim)

                Button("完成") {
                    viewModel.isFilterSheetPresented = false
                }
                .font(.system(size: Theme.Font.caption, weight: .semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(Color.white, in: Capsule())
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)

            FilterStrip(
                presets: viewModel.stripPresets,
                thumbnails: viewModel.thumbnails,
                selectedID: viewModel.selectedPreset.id,
                onSelect: { viewModel.selectPreset($0) },
                onOpenLibrary: { viewModel.isLibraryPresented = true }
            )

            if showsIntensity {
                IntensitySlider(
                    value: viewModel.intensity,
                    onChange: { viewModel.setIntensity($0) }
                )
            }

            Spacer(minLength: 0)
        }
        .padding(.bottom, 8)
        .presentationDetents([.height(showsIntensity ? 232 : 188)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.black)
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
    }
}

/// 底部弹出的参数面板：曝光、对比、色温、颗粒。
@MainActor
struct AdjustPanel: View {
    @ObservedObject var viewModel: CameraViewModel

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Spacer()
                Button("完成") {
                    viewModel.isAdjustSheetPresented = false
                }
                .font(.system(size: Theme.Font.caption, weight: .semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(Color.white, in: Capsule())
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            AdjustmentPanel(
                adjustments: viewModel.adjustments,
                onChange: { viewModel.setAdjustments($0) },
                onReset: { viewModel.resetAdjustments() }
            )

            Spacer(minLength: 0)
        }
        .padding(.bottom, 8)
        .presentationDetents([.height(262)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.black)
    }
}
