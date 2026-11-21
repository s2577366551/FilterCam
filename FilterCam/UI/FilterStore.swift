import Combine
import Foundation

@MainActor
final class FilterStore: ObservableObject {
    static let maxFavorites = 12
    static let maxRecents = 12
    static let stripLimit = 6

    @Published private(set) var favorites: [String]
    @Published private(set) var recents: [String]

    private let defaults: UserDefaults
    private let favoritesKey = "filter.favorites"
    private let recentsKey = "filter.recents"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.favorites = defaults.stringArray(forKey: favoritesKey) ?? []
        self.recents = defaults.stringArray(forKey: recentsKey) ?? []
    }

    func isFavorite(_ id: String) -> Bool {
        favorites.contains(id)
    }

    func toggleFavorite(_ id: String) {
        if let index = favorites.firstIndex(of: id) {
            favorites.remove(at: index)
        } else {
            favorites.insert(id, at: 0)
            if favorites.count > Self.maxFavorites {
                favorites.removeLast(favorites.count - Self.maxFavorites)
            }
        }
        defaults.set(favorites, forKey: favoritesKey)
    }

    func markUsed(_ id: String) {
        recents.removeAll { $0 == id }
        recents.insert(id, at: 0)
        if recents.count > Self.maxRecents {
            recents.removeLast(recents.count - Self.maxRecents)
        }
        defaults.set(recents, forKey: recentsKey)
    }

    var stripPresets: [FilterPreset] {
        var ids: [String] = []
        for id in favorites + recents where !ids.contains(id) {
            ids.append(id)
        }
        let presets = ids.compactMap { PresetCatalog.byID[$0] }
        return [FilterPreset.original] + presets.prefix(Self.stripLimit)
    }
}
