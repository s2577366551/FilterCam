import SwiftUI

/// 一次对焦指示器的状态：位置是屏幕坐标。
struct FocusReticle: Equatable, Identifiable {
    let id = UUID()
    let position: CGPoint
    let isLocked: Bool
}

struct FocusReticleView: View {
    let isLocked: Bool

    @State private var scale: CGFloat = 1.4
    @State private var opacity: Double = 0

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(tint, lineWidth: 1.6)
                .frame(width: 76, height: 76)

            Rectangle()
                .fill(tint)
                .frame(width: 1.4, height: 14)
            Rectangle()
                .fill(tint)
                .frame(width: 14, height: 1.4)

            if isLocked {
                Text("AE/AF 锁定")
                    .font(.system(size: Theme.Font.small, weight: .medium))
                    .foregroundStyle(tint)
                    .fixedSize()
                    .offset(y: 52)
            }
        }
        .scaleEffect(scale)
        .opacity(opacity)
        .onAppear {
            withAnimation(.spring(response: 0.26, dampingFraction: 0.72)) {
                scale = 1
                opacity = 1
            }
        }
    }

    private var tint: Color {
        isLocked ? Color.yellow : Color.white.opacity(0.95)
    }
}
