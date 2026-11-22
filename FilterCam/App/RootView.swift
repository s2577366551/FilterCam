import SwiftUI

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var crashReport: String?
    @State private var didCheck = false

    var body: some View {
        CameraScreen()
            .background(Theme.background.ignoresSafeArea())
            .onAppear {
                guard !didCheck else { return }
                didCheck = true
                crashReport = CrashLogger.takeDiagnostics()
                CrashLogger.breadcrumb("app launch")
            }
            .onChange(of: scenePhase) { _, phase in
                // 退到后台或进入多任务界面都算正常离开，避免下次启动误报崩溃。
                if phase == .background || phase == .inactive {
                    CrashLogger.markCleanExit()
                }
            }
            .sheet(isPresented: Binding(
                get: { crashReport != nil },
                set: { presented in
                    if !presented { crashReport = nil }
                }
            )) {
                CrashReportView(text: crashReport ?? "")
            }
    }
}
