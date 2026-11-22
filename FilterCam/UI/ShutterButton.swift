import SwiftUI

struct ShutterButton: View {
    var isBusy: Bool = false
    var isVideoMode: Bool = false
    var isRecording: Bool = false
    let action: () -> Void

    private var innerColor: Color {
        if isVideoMode {
            return Color(red: 1, green: 0.23, blue: 0.25)
        }
        return Color.white.opacity(isBusy ? 0.45 : 1)
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(isBusy ? 0.45 : 1), lineWidth: 4)
                    .frame(width: 72, height: 72)

                if isVideoMode && isRecording {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(innerColor)
                        .frame(width: 28, height: 28)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Circle()
                        .fill(innerColor)
                        .frame(width: 58, height: 58)
                }

                if isBusy {
                    ProgressView()
                        .tint(Color(white: 0.25))
                }
            }
            .frame(width: 88, height: 88)
            .contentShape(Circle())
            .animation(.easeInOut(duration: 0.18), value: isRecording)
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .accessibilityLabel(isVideoMode ? (isRecording ? "停止录制" : "开始录制") : "快门")
    }
}
