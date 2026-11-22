import SwiftUI

struct IntensitySlider: View {
    let value: Float
    let onChange: (Float) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "circle.lefthalf.filled")
                .font(.system(size: Theme.Font.iconCaption))
                .foregroundStyle(Theme.controlDim)

            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { onChange(Float($0)) }
                ),
                in: 0...1
            )
            .tint(.white)

            Text("\(Int(value * 100))%")
                .font(.system(size: Theme.Font.caption, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Theme.control)
                .frame(width: 44, alignment: .trailing)
        }
        .padding(.horizontal, 20)
    }
}
