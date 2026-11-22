import SwiftUI

@main
struct FilterCamApp: App {
    init() {
        CrashLogger.install()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .statusBarHidden()
        }
    }
}
