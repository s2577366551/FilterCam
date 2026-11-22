import SwiftUI

struct ToastView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: Theme.Font.caption, weight: .medium))
            .foregroundStyle(Theme.control)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Theme.overlay, in: Capsule())
            .transition(.opacity)
    }
}
