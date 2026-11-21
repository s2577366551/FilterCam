import SwiftUI

struct PermissionGateView: View {
    let title: String
    let message: String
    let showsSettingsButton: Bool
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.system(size: 44))
                .foregroundStyle(Theme.controlDim)

            Text(title)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.control)

            Text(message)
                .font(.system(size: 15))
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.controlDim)
                .padding(.horizontal, 32)

            if showsSettingsButton {
                Button("去设置") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(.black)
            }

            Button("重试", action: retry)
                .foregroundStyle(Theme.controlDim)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
    }
}
