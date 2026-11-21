import Foundation

struct FilterAdjustments: Equatable {
    var exposure: Float = 0
    var contrast: Float = 0
    var temperature: Float = 0
    var grain: Float = 0

    static let neutral = FilterAdjustments()

    var isNeutral: Bool { self == .neutral }

    func clamped() -> FilterAdjustments {
        FilterAdjustments(
            exposure: min(max(exposure, -1), 1),
            contrast: min(max(contrast, -1), 1),
            temperature: min(max(temperature, -1), 1),
            grain: min(max(grain, -1), 1)
        )
    }
}
