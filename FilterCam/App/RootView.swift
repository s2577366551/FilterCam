import SwiftUI

struct RootView: View {
    var body: some View {
        CameraScreen()
            .background(Theme.background.ignoresSafeArea())
    }
}
