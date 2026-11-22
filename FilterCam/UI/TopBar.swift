import SwiftUI

struct TopBar: View {
    let mode: CaptureMode
    let flashMode: FlashMode
    let isManualFocus: Bool
    let resolutionBadge: String
    let isLivePhoto: Bool
    let isDualCamera: Bool
    let isDualSupported: Bool
    let isRecording: Bool
    let onFlash: () -> Void
    let onManualFocus: () -> Void
    let onResolution: () -> Void
    let onLivePhoto: () -> Void
    let onDual: () -> Void
    let onFlip: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if mode == .photo {
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
            } else {
                pillButton(
                    title: "MF",
                    systemImage: nil,
                    isActive: isManualFocus,
                    action: onManualFocus
                )
            }

            Spacer(minLength: 4)

            iconButton(
                systemImage: "rectangle.on.rectangle",
                isActive: isDualCamera,
                label: "前后双摄",
                action: onDual
            )
            .opacity(isDualSupported ? 1 : 0.35)

            iconButton(
                systemImage: "arrow.triangle.2.circlepath.camera",
                isActive: false,
                label: "切换摄像头",
                action: onFlip
            )
            .opacity(isRecording || isDualCamera ? 0.4 : 1)
            .disabled(isRecording || isDualCamera)
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
                        .font(.system(size: Theme.Font.small, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: Theme.Font.small, weight: .semibold))
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

    private func iconButton(
        systemImage: String,
        isActive: Bool,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: Theme.Font.iconBody, weight: .medium))
                .foregroundStyle(isActive ? Color.black : Theme.control)
                .frame(width: 40, height: 40)
                .background(isActive ? Color.yellow : Theme.overlay, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var flashSymbol: String {
        switch flashMode {
        case .auto: return "bolt.badge.a"
        case .on: return "bolt.fill"
        case .off: return "bolt.slash"
        }
    }
}
