import Foundation

enum FilterCategory: String, CaseIterable, Identifiable {
    case simulation
    case classic
    case cinema
    case season
    case experimental

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .simulation: return "胶片模拟"
        case .classic: return "经典胶片"
        case .cinema: return "电影感"
        case .season: return "季节情绪"
        case .experimental: return "复古实验"
        }
    }
}

struct FilterPreset: Identifiable, Equatable, Hashable {
    let id: String
    let displayName: String
    let category: FilterCategory
    let lutName: String?
    let grain: Float
    let vignette: Float

    static let original = FilterPreset(
        id: "original",
        displayName: "原图",
        category: .simulation,
        lutName: nil,
        grain: 0,
        vignette: 0
    )
}
