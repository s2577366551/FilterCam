import SwiftUI

struct AdjustmentPanel: View {
    let adjustments: FilterAdjustments
    let onChange: (FilterAdjustments) -> Void
    let onReset: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text("调节")
                    .font(.system(size: Theme.Font.caption, weight: .semibold))
                    .foregroundStyle(Theme.controlDim)
                Spacer()
                Button("重置", action: onReset)
                    .font(.system(size: Theme.Font.caption))
                    .foregroundStyle(Theme.control)
            }
            .padding(.horizontal, 20)

            row("曝光", value: adjustments.exposure) { value in
                var next = adjustments
                next.exposure = value
                onChange(next)
            }
            row("对比", value: adjustments.contrast) { value in
                var next = adjustments
                next.contrast = value
                onChange(next)
            }
            row("色温", value: adjustments.temperature) { value in
                var next = adjustments
                next.temperature = value
                onChange(next)
            }
            row("颗粒", value: adjustments.grain) { value in
                var next = adjustments
                next.grain = value
                onChange(next)
            }
        }
    }

    private func row(
        _ title: String,
        value: Float,
        onChange: @escaping (Float) -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: Theme.Font.small))
                .foregroundStyle(Theme.controlDim)
                .frame(width: 32, alignment: .leading)
            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { onChange(Float($0)) }
                ),
                in: -1...1
            )
            .tint(.white)
        }
        .padding(.horizontal, 20)
    }
}
