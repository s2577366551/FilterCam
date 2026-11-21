import XCTest
@testable import FilterCam

final class FilterStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "FilterStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    @MainActor
    func testToggleFavoriteAddsAndRemoves() {
        let store = FilterStore(defaults: defaults)
        store.toggleFavorite("sim_chrome")
        XCTAssertTrue(store.isFavorite("sim_chrome"))
        store.toggleFavorite("sim_chrome")
        XCTAssertFalse(store.isFavorite("sim_chrome"))
    }

    @MainActor
    func testFavoritesAreCapped() {
        let store = FilterStore(defaults: defaults)
        for preset in PresetCatalog.all.prefix(20) {
            store.toggleFavorite(preset.id)
        }
        XCTAssertEqual(store.favorites.count, FilterStore.maxFavorites)
    }

    @MainActor
    func testRecentsMoveToFrontAndDeduplicate() {
        let store = FilterStore(defaults: defaults)
        store.markUsed("sim_chrome")
        store.markUsed("sim_vivid")
        store.markUsed("sim_chrome")
        XCTAssertEqual(store.recents, ["sim_chrome", "sim_vivid"])
    }

    @MainActor
    func testRecentsPersist() {
        let first = FilterStore(defaults: defaults)
        first.markUsed("sim_mono")
        let second = FilterStore(defaults: defaults)
        XCTAssertEqual(second.recents, ["sim_mono"])
    }

    @MainActor
    func testStripStartsWithOriginalAndRespectsLimit() {
        let store = FilterStore(defaults: defaults)
        for preset in PresetCatalog.all.prefix(10) {
            store.markUsed(preset.id)
        }
        XCTAssertEqual(store.stripIDs.first, FilterPreset.original.id)
        XCTAssertLessThanOrEqual(store.stripIDs.count, 7)
    }
}
