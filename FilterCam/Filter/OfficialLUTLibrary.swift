import Foundation

/// 富士官方 LUT（已预适配成可直接用于 sRGB 照片）。
struct OfficialLUT: Identifiable, Equatable {
    let id: String
    let name: String
    let group: String
    let camera: String
    let file: String
}

final class OfficialLUTLibrary {
    static let shared = OfficialLUTLibrary()

    private(set) var luts: [OfficialLUT] = []
    private var cache: [String: LUTData] = [:]
    private let lock = NSLock()
    private let dimension = 33

    private struct ManifestEntry: Decodable {
        let id: String
        let name: String
        let group: String
        let camera: String
        let file: String
    }

    private init() {
        loadManifest()
    }

    func lut(for id: String) throws -> LUTData? {
        lock.lock()
        defer { lock.unlock() }

        if let cached = cache[id] {
            return cached
        }
        guard let entry = luts.first(where: { $0.id == id }) else {
            return nil
        }
        let resourceName = (entry.file as NSString).deletingPathExtension
        let resourceExt = (entry.file as NSString).pathExtension
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: resourceExt) else {
            throw LUTError.missingResource(entry.file)
        }
        let data = try Data(contentsOf: url)
        let count = dimension * dimension * dimension
        guard data.count == count * 4 else {
            throw LUTError.invalidData(entry.file)
        }

        var floats = [Float](repeating: 1, count: count * 4)
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return }
            for index in 0..<count {
                let offset = index * 4
                floats[offset] = Float(base[offset]) / 255
                floats[offset + 1] = Float(base[offset + 1]) / 255
                floats[offset + 2] = Float(base[offset + 2]) / 255
                floats[offset + 3] = 1
            }
        }

        let lut = LUTData(
            dimension: dimension,
            data: floats.withUnsafeBufferPointer { Data(buffer: $0) }
        )
        cache[id] = lut
        return lut
    }

    private func loadManifest() {
        guard let url = Bundle.main.url(forResource: "official_luts", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([ManifestEntry].self, from: data) else {
            Log.filter.error("富士官方 LUT 清单加载失败")
            return
        }
        luts = decoded.map {
            OfficialLUT(
                id: $0.id,
                name: $0.name,
                group: $0.group,
                camera: $0.camera,
                file: $0.file
            )
        }
        Log.filter.info("富士官方 LUT: \(self.luts.count) 个")
    }
}
