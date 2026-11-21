import Foundation

enum FilterCategory: String, CaseIterable, Identifiable {
    case simulation
    case classic
    case cinema
    case season
    case experimental
    case mine

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .simulation: return "胶片模拟"
        case .classic: return "经典胶片"
        case .cinema: return "电影感"
        case .season: return "季节情绪"
        case .experimental: return "复古实验"
        case .mine: return "我的"
        }
    }
}

struct FilterPreset: Identifiable, Equatable, Hashable {
    let id: String
    let displayName: String
    let category: FilterCategory
    let lutName: String?
    let userLUTID: String?
    let grain: Float
    let vignette: Float

    init(
        id: String,
        displayName: String,
        category: FilterCategory,
        lutName: String?,
        userLUTID: String? = nil,
        grain: Float,
        vignette: Float
    ) {
        self.id = id
        self.displayName = displayName
        self.category = category
        self.lutName = lutName
        self.userLUTID = userLUTID
        self.grain = grain
        self.vignette = vignette
    }

    var hasLUT: Bool {
        lutName != nil || userLUTID != nil
    }

    static let original = FilterPreset(
        id: "original",
        displayName: "原图",
        category: .simulation,
        lutName: nil,
        grain: 0,
        vignette: 0
    )

    static func user(_ lut: UserLUT) -> FilterPreset {
        FilterPreset(
            id: "user_\(lut.id)",
            displayName: lut.displayName,
            category: .mine,
            lutName: nil,
            userLUTID: lut.id,
            grain: 0,
            vignette: 0
        )
    }
}
