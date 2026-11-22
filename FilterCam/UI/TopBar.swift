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
            pillButton(
                title: flashMode.displayName,
                systemImage: flashSymbol,
                isActive: flashMode != .auto,
                action: onFlash
            )

            pillButton(
                title: "MF",
                systemImage: nil,
                isActive: isManualFocus,
                action: onManualFocus
            )

            pillButton(
                title: resolutionBadge,
                systemImage: nil,
                isActive: resolutionBadge != "12M",
                action: onResolution
            )

            pillButton(
                title: "实况",
                systemImage: nil,
                isActive: isLivePhoto,
                action: onLivePhoto
            )

            Spacer(minLength: 4)

            Button(action: onFlip) {
                Image(systemName: "arrow.triangle.2.circlepath.camera")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.control)
                    .frame(width: 40, height: 40)
                    .background(Theme.overlay, in: Circle())
            }
            .accessibilityLabel("切换摄像头")
        }
        .padding(.horizontal, 14)
    }

    private func pillButton(
        title: String,
        systemImage: String?,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(isActive ? Color.black : Theme.control)
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(
                isActive ? Color.yellow : Theme.overlay,
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
    }

    private var flashSymbol: String {
        switch flashMode {
        case .auto: return "bolt.badge.a"
        case .on: return "bolt.fill"
        case .off: return "bolt.slash"
        }
    }
}
