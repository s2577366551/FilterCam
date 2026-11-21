import SwiftUI

struct TopBar: View {
    let flashMode: FlashMode
    let onFlash: () -> Void
    let onFlip: () -> Void

    var body: some View {
        HStack {
            Button(action: onFlash) {
                Label(flashMode.displayName, systemImage: flashSymbol)
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.control)
                    .padding(.horizontal, 12)
                    .frame(height: Theme.hitTarget)
                    .background(Theme.overlay, in: Capsule())
            }

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
