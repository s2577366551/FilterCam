import XCTest
@testable import FilterCam

final class PresetCatalogTests: XCTestCase {
    func testCatalogHasFortyThreeEntries() {
        XCTAssertEqual(PresetCatalog.all.count, 43)
    }

    func testIdentifiersAreUnique() {
        let ids = PresetCatalog.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testDisplayNamesAreNotEmpty() {
        XCTAssertTrue(PresetCatalog.all.allSatisfy { !$0.displayName.isEmpty })
    }

    func testEveryPresetExceptOriginalHasLUT() {
        for preset in PresetCatalog.all where preset.id != FilterPreset.original.id {
            XCTAssertNotNil(preset.lutName, "\(preset.id) 缺少 LUT")
        }
    }

    func testEveryCategoryHasPresets() {
        for category in FilterCategory.allCases where category != .mine {
            XCTAssertFalse(PresetCatalog.presets(in: category).isEmpty, "\(category) 为空")
        }
    }

    func testOriginalIsFirst() {
        XCTAssertEqual(PresetCatalog.all.first, FilterPreset.original)
    }
}
