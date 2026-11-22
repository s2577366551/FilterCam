import SwiftUI
import UIKit

/// 上次运行崩溃时显示诊断信息，方便直接复制发出来。
struct CrashReportView: View {
    let text: String
    @Environment(\.dismiss) private var dismiss
    @State private var didCopy = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                VStack(spacing: 14) {
                    Text("上次运行闪退了")
                        .font(.system(size: Theme.Font.title, weight: .semibold))
                        .foregroundStyle(Theme.control)

                    Text("下面是 App 自己记录的原因和最近步骤，复制发给我就能定位。")
                        .font(.system(size: Theme.Font.body))
                        .lineSpacing(6)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.controlDim)
                        .padding(.horizontal, 8)

                    ScrollView {
                        Text(text)
                            .font(.system(size: Theme.Font.small, design: .monospaced))
                            .foregroundStyle(Theme.control)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(12)
                    }
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))

                    HStack(spacing: 10) {
                        Button {
                            UIPasteboard.general.string = text
                            didCopy = true
                            Haptics.selection()
                        } label: {
                            Label(didCopy ? "已复制" : "复制全部", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                                .font(.system(size: Theme.Font.body, weight: .medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.white.opacity(0.14), in: Capsule())
                                .foregroundStyle(Theme.control)
                        }

                        Button {
                            dismiss()
                        } label: {
                            Text("关闭")
                                .font(.system(size: Theme.Font.body, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.white, in: Capsule())
                                .foregroundStyle(.black)
                        }
                    }
                }
                .padding(18)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}
