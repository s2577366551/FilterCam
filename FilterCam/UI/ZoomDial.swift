import SwiftUI

/// 苹果相机那种弧形变焦盘：沿弧线拖动改变倍数。
struct ZoomDial: View {
    let value: CGFloat
    let range: ClosedRange<CGFloat>
    let stops: [CGFloat]
    let onChange: (CGFloat) -> Void
    let onInteractionEnded: () -> Void

    private let startDegrees: Double = 232
    private let sweepDegrees: Double = 76

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let radius = size.width * 0.66
            let center = CGPoint(x: size.width / 2, y: 40 + radius)
            let dialRange = effectiveRange
            let angle = startDegrees + sweepDegrees * fraction(for: value, in: dialRange)

            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.black.opacity(0.62))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )

                arc(center: center, radius: radius)
                    .stroke(
                        Color.white.opacity(0.30),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )

                ForEach(0...20, id: \.self) { index in
                    tick(index: index, center: center, radius: radius)
                }

                Text(displayText)
                    .font(.system(size: 26, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(isDefault ? Theme.control : Color.yellow)
                    .shadow(color: .black.opacity(0.55), radius: 3, y: 1)
                    .position(x: size.width / 2, y: 82)
                    .allowsHitTesting(false)

                Circle()
                    .fill(Color.white)
                    .frame(width: 10, height: 10)
                    .shadow(color: .black.opacity(0.45), radius: 2)
                    .position(point(center: center, radius: radius, degrees: angle))
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let raw = angleDegrees(from: gesture.location, center: center)
                        let t = min(max((raw - startDegrees) / sweepDegrees, 0), 1)
                        let snapped = snappedFraction(t, in: dialRange)
                        onChange(value(forFraction: snapped, in: dialRange))
                    }
                    .onEnded { _ in onInteractionEnded() }
            )
        }
    }

    // MARK: - 绘制

    private func arc(center: CGPoint, radius: CGFloat) -> Path {
        Path { path in
            path.addArc(
                center: center,
                radius: radius,
                startAngle: .degrees(startDegrees),
                endAngle: .degrees(startDegrees + sweepDegrees),
                clockwise: false
            )
        }
    }

    private func tick(index: Int, center: CGPoint, radius: CGFloat) -> some View {
        let t = Double(index) / 20
        let degrees = startDegrees + sweepDegrees * t
        let isMajor = index % 5 == 0
        let inner = radius + 2
        let outer = radius + (isMajor ? 11 : 6)
        return Path { path in
            path.move(to: point(center: center, radius: inner, degrees: degrees))
            path.addLine(to: point(center: center, radius: outer, degrees: degrees))
        }
        .stroke(
            Color.white.opacity(isMajor ? 0.55 : 0.25),
            style: StrokeStyle(lineWidth: isMajor ? 1.6 : 1, lineCap: .round)
        )
    }

    private func point(center: CGPoint, radius: CGFloat, degrees: Double) -> CGPoint {
        let radians = degrees * .pi / 180
        return CGPoint(
            x: center.x + CGFloat(cos(radians)) * radius,
            y: center.y + CGFloat(sin(radians)) * radius
        )
    }

    private func angleDegrees(from point: CGPoint, center: CGPoint) -> Double {
        let dx = Double(point.x - center.x)
        let dy = Double(point.y - center.y)
        var degrees = atan2(dy, dx) * 180 / .pi
        if degrees > 0 { degrees -= 360 }
        return degrees
    }

    // MARK: - 映射

    private var effectiveRange: ClosedRange<CGFloat> {
        let low = max(range.lowerBound, 0.5)
        let high = max(min(range.upperBound, 15), low * 1.05)
        return low...high
    }

    private var isDefault: Bool {
        abs(value - 1) < 0.05
    }

    private var displayText: String {
        if abs(value - value.rounded()) < 0.05 {
            return String(format: "%.0f×", value)
        }
        return String(format: "%.1f×", value)
    }

    private func fraction(for value: CGFloat, in range: ClosedRange<CGFloat>) -> Double {
        let low = max(Double(range.lowerBound), 0.01)
        let high = max(Double(range.upperBound), low * 1.01)
        let clamped = min(max(Double(value), low), high)
        return log(clamped / low) / log(high / low)
    }

    private func value(forFraction t: Double, in range: ClosedRange<CGFloat>) -> CGFloat {
        let low = max(Double(range.lowerBound), 0.01)
        let high = max(Double(range.upperBound), low * 1.01)
        return CGFloat(low * pow(high / low, min(max(t, 0), 1)))
    }

    private func snappedFraction(_ t: Double, in range: ClosedRange<CGFloat>) -> Double {
        for stop in stops where range.contains(stop) {
            let stopT = fraction(for: stop, in: range)
            if abs(stopT - t) < 0.012 {
                return stopT
            }
        }
        return t
    }
}
