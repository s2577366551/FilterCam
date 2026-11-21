import SwiftUI

struct ShutterButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(Color.white, lineWidth: 4)
                    .frame(width: 72, height: 72)
                Circle()
                    .fill(Color.white)
                    .frame(width: 58, height: 58)
            }
            .frame(width: 88, height: 88)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("快门")
    }
}
