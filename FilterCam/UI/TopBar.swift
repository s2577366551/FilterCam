import SwiftUI

struct TopBar: View {
    let flashMode: FlashMode
    let isManualFocus: Bool
    let resolutionBadge: String
    let isLivePhoto: Bool
    let onFlash: () -> Void
    let onManualFocus: () -> Void
    let onResolution: () -> Void
    let onLivePhoto: () -> Void
    let onFlip: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onFlash) {
                Label(flashMode.displayName, systemImage: flashSymbol)
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.control)
                    .padding(.horizontal, 10)
                    .frame(height: Theme.hitTarget)
                    .background(Theme.overlay, in: Capsule())
            }

            Button(action: onManualFocus) {
                Text("MF")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isManualFocus ? Color.black : Theme.control)
                    .padding(.horizontal, 12)
                    .frame(height: Theme.hitTarget)
                    .background(
                        isManualFocus ? Color.yellow : Theme.overlay,
                        in: Capsule()
                    )
            }
            .accessibilityLabel("手动对焦")

            Button(action: onResolution) {
                Text(resolutionBadge)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.control)
                    .padding(.horizontal, 10)
                    .frame(height: Theme.hitTarget)
                    .background(Theme.overlay, in: Capsule())
            }
            .accessibilityLabel("拍照分辨率")

            Button(action: onLivePhoto) {
                Image(systemName: "livephoto")
                    .font(.system(size: 17))
                    .foregroundStyle(isLivePhoto ? Color.yellow : Theme.controlDim)
                    .frame(width: Theme.hitTarget, height: Theme.hitTarget)
                    .background(Theme.overlay, in: Circle())
            }
            .accessibilityLabel("实况照片")

            Spacer()

            Button(action: onFlip) {
                Image(systemName: "arrow.triangle.2.circlepath.camera")
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.control)
                    .frame(width: Theme.hitTarget, height: Theme.hitTarget)
                    .background(Theme.overlay, in: Circle())
            }
        }
        .padding(.horizontal, 16)
    }

    private var flashSymbol: String {
        switch flashMode {
        case .auto: return "bolt.badge.a"
        case .on: return "bolt.fill"
        case .off: return "bolt.slash"
        }
    }
}
