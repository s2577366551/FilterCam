import Foundation

protocol LUTResolving {
    func lut(for preset: FilterPreset) throws -> LUTData?
}

final class CompositeLUTResolver: LUTResolving {
    private let bundled: LUTLoading
    private let user: UserLUTLibrary

    init(bundled: LUTLoading, user: UserLUTLibrary) {
        self.bundled = bundled
        self.user = user
    }

    func lut(for preset: FilterPreset) throws -> LUTData? {
        if let id = preset.userLUTID {
            return try user.lut(for: id)
        }
        if let name = preset.lutName {
            return try bundled.load(named: name)
        }
        return nil
    }
}

final class BundledLUTResolver: LUTResolving {
    private let loader: LUTLoading

    init(loader: LUTLoading) {
        self.loader = loader
    }

    func lut(for preset: FilterPreset) throws -> LUTData? {
        guard let name = preset.lutName else { return nil }
        return try loader.load(named: name)
    }
}
