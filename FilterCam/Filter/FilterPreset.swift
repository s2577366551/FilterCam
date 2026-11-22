import Foundation

enum FilterCategory: String, CaseIterable, Identifiable {
    case simulation
    case classic
    case cinema
    case season
    case experimental
    case official
    case mine

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .simulation: return "胶片模拟"
        case .classic: return "经典胶片"
        case .cinema: return "电影感"
        case .season: return "季节情绪"
        case .experimental: return "复古实验"
        case .official: return "富士官方"
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
    let officialLUTID: String?
    let grain: Float
    let vignette: Float

    init(
        id: String,
        displayName: String,
        category: FilterCategory,
        lutName: String?,
        userLUTID: String? = nil,
        officialLUTID: String? = nil,
        grain: Float,
        vignette: Float
    ) {
        self.id = id
        self.displayName = displayName
        self.category = category
        self.lutName = lutName
        self.userLUTID = userLUTID
        self.officialLUTID = officialLUTID
        self.grain = grain
        self.vignette = vignette
    }

    var hasLUT: Bool {
        lutName != nil || userLUTID != nil || officialLUTID != nil
    }

    /// 滤镜条上显示的短名字：去掉富士官方文件名的前后缀，避免把布局撑开。
    var stripName: String {
        if category == .official {
            var short = displayName
            if let range = short.range(of: " · ") {
                short = String(short[..<range.lowerBound])
            }
            if let range = short.range(of: " (") {
                short = String(short[..<range.lowerBound])
            }
            return short
        }

        var name = displayName

        // 前缀大小写都可能不同（FLog2 / Flog2 / flog2）。
        let lower = name.lowercased()
        for prefix in ["flog2_to_", "flog2-to-", "flog2_to", "flog2_", "flog2-", "flog2 "] {
            if lower.hasPrefix(prefix) {
                name = String(name.dropFirst(prefix.count))
                break
            }
        }

        // 去掉常见的版本/网格后缀。
        for marker in ["_33grid", "-33grid", "_33", "-33", "_v1.00", "_v1.0", "_v1", "-v1", ".cube"] {
            if let range = name.range(of: marker, options: .caseInsensitive) {
                name = String(name[..<range.lowerBound])
            }
        }

        name = name
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // 还是太长就截断，保证 56pt 宽度里能显示完整的意思。
        if name.count > 12 {
            name = String(name.prefix(12))
        }
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

    static func official(_ lut: OfficialLUT) -> FilterPreset {
        FilterPreset(
            id: "official_\(lut.id)",
            displayName: lut.name,
            category: .official,
            lutName: nil,
            officialLUTID: lut.id,
            grain: 0,
            vignette: 0
        )
    }
}
