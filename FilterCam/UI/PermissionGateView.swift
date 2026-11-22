import SwiftUI
import UIKit

struct PermissionGateView: View {
    let title: String
    let message: String
    let showsSettingsButton: Bool
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.system(size: 48))
                .foregroundStyle(Theme.controlDim)

            Text(title)
                .font(.system(size: Theme.Font.title, weight: .semibold))
                .foregroundStyle(Theme.control)

            Text(message)
                .font(.system(size: Theme.Font.body))
                .lineSpacing(6)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.controlDim)
                .padding(.horizontal, 32)

            if showsSettingsButton {
                Button("去设置") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }
                .font(.system(size: Theme.Font.body, weight: .medium))
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(.black)
            }

            Button("重试", action: retry)
                .font(.system(size: Theme.Font.body))
                .foregroundStyle(Theme.controlDim)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
    }
}
