import SwiftUI

struct RootView: View {
    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            Text("FilterCam")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Theme.control)
        }
    }
}
