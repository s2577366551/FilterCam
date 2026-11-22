import SwiftUI

struct ShutterButton: View {
    var isBusy: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(isBusy ? 0.45 : 1), lineWidth: 4)
                    .frame(width: 72, height: 72)
                Circle()
                    .fill(Color.white.opacity(isBusy ? 0.45 : 1))
                    .frame(width: 58, height: 58)
                if isBusy {
                    ProgressView()
                        .tint(Color(white: 0.25))
                }
            }
            .frame(width: 88, height: 88)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .accessibilityLabel("快门")
    }
}
