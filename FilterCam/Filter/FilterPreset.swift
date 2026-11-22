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

    /// 滤镜条上显示的短名字：去掉富士官方文件名的前后缀，避免把布局撑开。
    var stripName: String {
        var name = displayName
        for prefix in ["FLog2_to_", "FLog2-to-", "FLog2_to", "FLog2 "] where name.hasPrefix(prefix) {
            name.removeFirst(prefix.count)
            break
        }
        for marker in ["_33grid", "_33Grid", "_V.1", "_v1", ".cube"] {
            if let range = name.range(of: marker) {
                name = String(name[..<range.lowerBound])
            }
        }
        name = name
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? displayName : name
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
