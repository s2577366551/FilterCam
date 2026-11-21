import CoreImage
import CoreGraphics

enum LUTError: Error, Equatable {
    case missingResource(String)
    case invalidImage(String)
    case invalidData(String)
}

protocol LUTLoading {
    func colorCube(named name: String) throws -> CIColorCube
}

final class LUTLoader: LUTLoading {
    static let dimension = 32

    private static let conversionContext = CIContext(options: [
        .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any
    ])

    private var cache: [String: CIColorCube] = [:]
    private let lock = NSLock()

    func colorCube(named name: String) throws -> CIColorCube {
        lock.lock()
        defer { lock.unlock() }

        if let cached = cache[name] {
            return cached
        }
        guard let url = Bundle.main.url(forResource: name, withExtension: "png") else {
            throw LUTError.missingResource(name)
        }
        guard let image = CIImage(contentsOf: url) else {
            throw LUTError.invalidImage(name)
        }
        let expectedWidth = CGFloat(LUTLoader.dimension * LUTLoader.dimension)
        let expectedHeight = CGFloat(LUTLoader.dimension)
        guard image.extent.width == expectedWidth, image.extent.height == expectedHeight else {
            throw LUTError.invalidData(name)
        }
        guard let cgImage = Self.conversionContext.createCGImage(image, from: image.extent) else {
            throw LUTError.invalidImage(name)
        }

        let data = try Self.makeCubeData(from: cgImage, name: name)
        let cube = CIColorCube()
        cube.dimension = Float(LUTLoader.dimension)
        cube.cubeData = data
        cache[name] = cube
        return cube
    }

    private static func makeCubeData(from image: CGImage, name: String) throws -> Data {
        let n = dimension
        let width = n * n
        let height = n
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        let created = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard created else {
            throw LUTError.invalidData(name)
        }

        let count = n * n * n
        var floats = [Float](repeating: 1, count: count * 4)
        for index in 0..<count {
            let offset = index * 4
            floats[offset] = Float(bytes[offset]) / 255.0
            floats[offset + 1] = Float(bytes[offset + 1]) / 255.0
            floats[offset + 2] = Float(bytes[offset + 2]) / 255.0
            floats[offset + 3] = 1.0
        }
        return floats.withUnsafeBufferPointer { Data(buffer: $0) }
    }
}
