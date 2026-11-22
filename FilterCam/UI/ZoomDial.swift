import SwiftUI

/// 变焦档位（0.5 / 1 / 2 / 3 / 最远）。
struct ZoomStop: Identifiable, Equatable {
    let value: CGFloat
    let label: String
    let millimeters: String?
    var id: CGFloat { value }
}

/// 苹果相机那种弧形变焦盘：深色面板，上沿是刻度弧，档位标在弧内。
struct ZoomDial: View {
    let value: CGFloat
    let range: ClosedRange<CGFloat>
    let stops: [ZoomStop]
    let onChange: (CGFloat) -> Void
    let onInteractionEnded: () -> Void

    private let startDegrees: Double = 222
    private let sweepDegrees: Double = 96
    private let apex: CGFloat = 40

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let radius = size.width * 0.62
            let center = CGPoint(x: size.width / 2, y: apex + radius)
            let dialRange = effectiveRange
            let currentT = fraction(for: value, in: dialRange)
            let currentAngle = startDegrees + sweepDegrees * currentT
            let nearest = stops.min { abs($0.value - value) < abs($1.value - value) }
            let isAtStop = nearest.map { abs($0.value - value) < 0.05 } ?? false

            ZStack(alignment: .topLeading) {
                panel(center: center, radius: radius, size: size)
                arc(center: center, radius: radius)
                ticks(center: center, radius: radius)

                ForEach(stops) { stop in
                    if !(stop.value == nearest?.value && !isAtStop) {
                        stopLabel(
                            stop: stop,
                            isActive: isAtStop && stop.value == nearest?.value,
                            center: center,
                            radius: radius
                        )
                    }
                }

                if !isAtStop {
                    Text(formatted(value))
                        .font(.system(size: 18, weight: .bold).monospacedDigit())
                        .foregroundStyle(Color.yellow)
                        .position(point(center: center, radius: radius - 38, degrees: currentAngle))
                }

                Image(systemName: "arrowtriangle.up.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.yellow)
                    .position(point(center: center, radius: radius + 1, degrees: currentAngle))
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

    private func panel(center: CGPoint, radius: CGFloat, size: CGSize) -> some View {
        let start = point(center: center, radius: radius, degrees: startDegrees)
        return Path { path in
            path.move(to: CGPoint(x: 0, y: size.height))
            path.addLine(to: CGPoint(x: 0, y: start.y))
            path.addLine(to: start)
            path.addArc(
                center: center,
                radius: radius,
                startAngle: .degrees(startDegrees),
                endAngle: .degrees(startDegrees + sweepDegrees),
                clockwise: false
            )
            path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.closeSubpath()
        }
        .fill(
            LinearGradient(
                colors: [Color.black.opacity(0.45), Color.black.opacity(0.78)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func arc(center: CGPoint, radius: CGFloat) -> some View {
        Path { path in
            path.addArc(
                center: center,
                radius: radius,
                startAngle: .degrees(startDegrees),
                endAngle: .degrees(startDegrees + sweepDegrees),
                clockwise: false
            )
        }
        .stroke(Color.white.opacity(0.28), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
    }

    private func ticks(center: CGPoint, radius: CGFloat) -> some View {
        ForEach(0...48, id: \.self) { index in
            let t = Double(index) / 48
            let degrees = startDegrees + sweepDegrees * t
            let isMajor = index % 4 == 0
            Path { path in
                path.move(to: point(center: center, radius: radius + 2, degrees: degrees))
                path.addLine(to: point(center: center, radius: radius + (isMajor ? 13 : 7), degrees: degrees))
            }
            .stroke(
                Color.white.opacity(isMajor ? 0.65 : 0.28),
                style: StrokeStyle(lineWidth: isMajor ? 1.5 : 1, lineCap: .round)
            )
        }
    }

    private func stopLabel(
        stop: ZoomStop,
        isActive: Bool,
        center: CGPoint,
        radius: CGFloat
    ) -> some View {
        let t = fraction(for: stop.value, in: effectiveRange)
        let degrees = startDegrees + sweepDegrees * t
        return VStack(spacing: 1) {
            Text(stop.label + (isActive ? "×" : ""))
                .font(.system(size: isActive ? 18 : 15, weight: isActive ? .bold : .medium))
                .foregroundStyle(isActive ? Color.yellow : Color.white.opacity(0.72))
            if let millimeters = stop.millimeters {
                Text(millimeters)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isActive ? Color.yellow.opacity(0.85) : Color.white.opacity(0.32))
            }
        }
        .position(point(center: center, radius: radius - 38, degrees: degrees))
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

    private func formatted(_ value: CGFloat) -> String {
        value < 10 ? String(format: "%.1f×", value) : String(format: "%.0f×", value)
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
        for stop in stops where range.contains(stop.value) {
            let stopT = fraction(for: stop.value, in: range)
            if abs(stopT - t) < 0.014 {
                return stopT
            }
        }
        return t
    }
}
