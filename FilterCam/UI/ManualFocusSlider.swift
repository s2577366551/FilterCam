import SwiftUI

struct ManualFocusSlider: View {
    let value: Float
    let onChange: (Float) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text("对焦")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.controlDim)

            Image(systemName: "mountain.2")
                .font(.system(size: 11))
                .foregroundStyle(Theme.controlDim)

            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { onChange(Float($0)) }
                ),
                in: 0...1
            )
            .tint(.yellow)

            Image(systemName: "mountain.2.fill")
                .font(.system(size: 11))
                .foregroundStyle(Theme.controlDim)

            Text(value >= 0.985 ? "∞" : "\(Int(value * 100))")
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Theme.control)
                .frame(width: 34, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
        .background(Theme.overlay, in: Capsule())
        .padding(.horizontal, 16)
    }
}
