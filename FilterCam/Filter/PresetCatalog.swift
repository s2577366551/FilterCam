import Foundation

enum PresetCatalog {
    static let all: [FilterPreset] =
        [FilterPreset.original]
        + filmPresets
        + classicPresets
        + cinemaPresets
        + seasonPresets
        + experimentalPresets

    static let byID: [String: FilterPreset] = Dictionary(
        uniqueKeysWithValues: all.map { ($0.id, $0) }
    )

    static func presets(in category: FilterCategory) -> [FilterPreset] {
        all.filter { $0.category == category }
    }

    private static func make(
        _ id: String,
        _ name: String,
        _ category: FilterCategory,
        grain: Float = 0.12,
        vignette: Float = 0.18
    ) -> FilterPreset {
        FilterPreset(
            id: id,
            displayName: name,
            category: category,
            lutName: id,
            grain: grain,
            vignette: vignette
        )
    }

    private static let filmPresets: [FilterPreset] = [
        make("sim_standard", "标准正片", .simulation, grain: 0.06, vignette: 0.08),
        make("sim_vivid", "鲜艳正片", .simulation, grain: 0.08, vignette: 0.12),
        make("sim_soft", "柔彩正片", .simulation, grain: 0.10, vignette: 0.10),
        make("sim_chrome", "经典正片", .simulation, grain: 0.14, vignette: 0.20),
        make("sim_negative", "经典负片", .simulation, grain: 0.16, vignette: 0.22),
        make("sim_nostalgic", "怀旧负片", .simulation, grain: 0.18, vignette: 0.24),
        make("sim_cinema", "电影负片", .simulation, grain: 0.12, vignette: 0.16),
        make("sim_bleach", "漂白负片", .simulation, grain: 0.20, vignette: 0.26),
        make("sim_mono", "细腻黑白", .simulation, grain: 0.08, vignette: 0.12),
        make("sim_mono_red", "黑白红调", .simulation, grain: 0.10, vignette: 0.14)
    ]

    private static let classicPresets: [FilterPreset] = [
        make("warm_portrait", "暖调人像", .classic, grain: 0.08, vignette: 0.12),
        make("cool_portrait", "冷调人像", .classic, grain: 0.08, vignette: 0.12),
        make("golden_day", "金色日光", .classic, grain: 0.14, vignette: 0.18),
        make("vivid_landscape", "鲜锐风景", .classic, grain: 0.06, vignette: 0.10),
        make("daily_street", "日常街拍", .classic, grain: 0.16, vignette: 0.18),
        make("coarse_mono", "粗颗粒黑白", .classic, grain: 0.34, vignette: 0.28),
        make("high_contrast_mono", "高反差黑白", .classic, grain: 0.18, vignette: 0.24),
        make("tungsten_night", "夜景钨丝", .classic, grain: 0.22, vignette: 0.30),
        make("instant", "拍立得", .classic, grain: 0.14, vignette: 0.22),
        make("retro_red", "复古红调", .classic, grain: 0.16, vignette: 0.22)
    ]

    private static let cinemaPresets: [FilterPreset] = [
        make("teal_orange", "青橙电影", .cinema, grain: 0.10, vignette: 0.20),
        make("bleach_bypass", "漂白", .cinema, grain: 0.14, vignette: 0.22),
        make("cross_process", "交叉冲洗", .cinema, grain: 0.18, vignette: 0.24),
        make("faded_matte", "褪色哑光", .cinema, grain: 0.12, vignette: 0.16),
        make("warm_cinema", "暖调电影", .cinema, grain: 0.10, vignette: 0.18),
        make("cool_noir", "冷调黑色", .cinema, grain: 0.12, vignette: 0.26),
        make("neon_night", "霓虹夜景", .cinema, grain: 0.16, vignette: 0.28),
        make("desert", "沙丘暖沙", .cinema, grain: 0.14, vignette: 0.20)
    ]

    private static let seasonPresets: [FilterPreset] = [
        make("spring", "春日", .season, grain: 0.08, vignette: 0.12),
        make("summer", "盛夏", .season, grain: 0.08, vignette: 0.14),
        make("autumn", "秋日", .season, grain: 0.12, vignette: 0.18),
        make("winter", "冬日", .season, grain: 0.08, vignette: 0.14),
        make("rainy", "雨天", .season, grain: 0.14, vignette: 0.18),
        make("sunset", "黄昏", .season, grain: 0.10, vignette: 0.20),
        make("dawn", "清晨", .season, grain: 0.08, vignette: 0.14),
        make("forest", "森林", .season, grain: 0.12, vignette: 0.22)
    ]

    private static let experimentalPresets: [FilterPreset] = [
        make("sepia", "棕褐", .experimental, grain: 0.18, vignette: 0.28),
        make("cyanotype", "蓝晒", .experimental, grain: 0.16, vignette: 0.26),
        make("infrared", "红外", .experimental, grain: 0.12, vignette: 0.22),
        make("lomo", "LOMO", .experimental, grain: 0.16, vignette: 0.42),
        make("duotone_purple", "紫调双色", .experimental, grain: 0.12, vignette: 0.24),
        make("negative", "负片反转", .experimental, grain: 0.14, vignette: 0.22)
    ]
}
