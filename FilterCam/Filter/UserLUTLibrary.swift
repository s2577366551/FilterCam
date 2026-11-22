import Combine
import Foundation

struct UserLUT: Codable, Identifiable, Equatable {
    let id: String
    var displayName: String
    let fileName: String
    let dimension: Int
    var isFLog2: Bool
    let importedAt: Date
}

final class UserLUTLibrary: ObservableObject {
    static let shared = UserLUTLibrary()

    @Published private(set) var luts: [UserLUT] = []

    private let lock = NSLock()
    private var entries: [UserLUT] = []
    private var cubeCache: [String: CubeLUT] = [:]
    private var dataCache: [String: LUTData] = [:]
    private let directory: URL
    private let indexURL: URL
    private let fileManager: FileManager

    init(directory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let directory {
            self.directory = directory
        } else {
            let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            self.directory = documents.appendingPathComponent("LUTs", isDirectory: true)
        }
        self.indexURL = self.directory.appendingPathComponent("index.json")
        try? fileManager.createDirectory(at: self.directory, withIntermediateDirectories: true)
        loadIndex()
    }

    func currentLUTs() -> [UserLUT] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }

    func lut(for id: String) throws -> LUTData? {
        lock.lock()
        defer { lock.unlock() }

        if let cached = dataCache[id] {
            return cached
        }
        guard let entry = entries.first(where: { $0.id == id }) else {
            return nil
        }

        let cube: CubeLUT
        if let cached = cubeCache[id] {
            cube = cached
        } else {
            let url = directory.appendingPathComponent(entry.fileName)
            cube = try CubeLUTParser.parse(data: Data(contentsOf: url))
            cubeCache[id] = cube
        }

        let result: LUTData
        if entry.isFLog2 {
            result = FLog2Adapter.adapt(cube)
        } else {
            result = LUTData(dimension: cube.dimension, data: cube.rgbaData)
        }
        dataCache[id] = result
        return result
    }

    func importLUT(from url: URL, isFLog2: Bool) throws -> UserLUT {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: url)
        guard data.count <= CubeLUTParser.maxBytes else {
            throw CubeLUTError.tooLarge
        }
        let cube = try CubeLUTParser.parse(data: data)

        let id = UUID().uuidString
        let fileName = "\(id).cube"
        let destination = directory.appendingPathComponent(fileName)
        try data.write(to: destination, options: .atomic)

        let fallbackName = url.deletingPathExtension().lastPathComponent
        let displayName = cube.title?.isEmpty == false ? cube.title! : fallbackName
        let entry = UserLUT(
            id: id,
            displayName: displayName,
            fileName: fileName,
            dimension: cube.dimension,
            isFLog2: isFLog2,
            importedAt: Date()
        )

        lock.lock()
        entries.append(entry)
        cubeCache[id] = cube
        saveIndexLocked()
        lock.unlock()

        publish()
        return entry
    }

    func delete(_ id: String) {
        lock.lock()
        guard let index = entries.firstIndex(where: { $0.id == id }) else {
            lock.unlock()
            return
        }
        let entry = entries.remove(at: index)
        cubeCache[id] = nil
        dataCache[id] = nil
        try? fileManager.removeItem(at: directory.appendingPathComponent(entry.fileName))
        saveIndexLocked()
        lock.unlock()

        publish()
    }

    /// 切换 LUT 的输入类型，并清掉已缓存的转换结果。
    func setInputType(_ id: String, isFLog2: Bool) {
        lock.lock()
        if let index = entries.firstIndex(where: { $0.id == id }) {
            entries[index].isFLog2 = isFLog2
            dataCache[id] = nil
            saveIndexLocked()
        }
        lock.unlock()

        publish()
    }

    func rename(_ id: String, to name: String) {        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        lock.lock()
        if let index = entries.firstIndex(where: { $0.id == id }) {
            entries[index].displayName = trimmed
            saveIndexLocked()
        }
        lock.unlock()

        publish()
    }

    private func publish() {
        lock.lock()
        let snapshot = entries
        lock.unlock()
        DispatchQueue.main.async {
            self.luts = snapshot
        }
    }

    private func loadIndex() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([UserLUT].self, from: data) else {
            return
        }
        lock.lock()
        entries = decoded
        lock.unlock()
        luts = decoded
    }

    private func saveIndexLocked() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }
}
