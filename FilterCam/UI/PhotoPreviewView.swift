import SwiftUI

/// 全屏查看刚拍的照片：双指缩放、拖动、双击复位。
struct PhotoPreviewView: View {
    let image: UIImage
    let onClose: () -> Void

    @State private var scale: CGFloat = 1
    @State private var committedScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var committedOffset: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .offset(offset)
                .gesture(magnification.simultaneously(with: drag))
                .onTapGesture(count: 2) { toggleZoom() }
                .animation(.easeOut(duration: 0.2), value: scale)
                .animation(.easeOut(duration: 0.2), value: offset)

            VStack {
                HStack {
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .accessibilityLabel("关闭")
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                Spacer()

                if scale <= 1.01 {
                    Text("双指放大 · 双击缩放")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.bottom, 24)
                        .transition(.opacity)
                }
            }
        }
        .statusBarHidden()
    }

    private var magnification: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = min(max(committedScale * value.magnification, 1), 6)
            }
            .onEnded { _ in
                committedScale = scale
                if scale <= 1.01 {
                    resetPosition()
                }
            }
    }

    private var drag: some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > 1.01 else { return }
                offset = CGSize(
                    width: committedOffset.width + value.translation.width,
                    height: committedOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                committedOffset = offset
            }
    }

    private func toggleZoom() {
        if scale > 1.01 {
            resetPosition()
        } else {
            scale = 2.5
            committedScale = 2.5
        }
    }

    private func resetPosition() {
        scale = 1
        committedScale = 1
        offset = .zero
        committedOffset = .zero
    }
}
