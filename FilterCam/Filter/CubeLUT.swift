import Foundation

struct CubeLUT {
    let title: String?
    let dimension: Int
    /// RGBA Float32，索引顺序 r 最快、b 最慢（r + g*N + b*N²）。
    let rgba: [Float]

    var rgbaData: Data {
        rgba.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    func sample(_ point: SIMD3<Float>) -> SIMD3<Float> {
        let n = dimension
        guard n > 1 else { return .zero }

        let maxIndex = Float(n - 1)
        let x = min(max(point.x, 0), 1) * maxIndex
        let y = min(max(point.y, 0), 1) * maxIndex
        let z = min(max(point.z, 0), 1) * maxIndex

        let x0 = Int(x.rounded(.down))
        let y0 = Int(y.rounded(.down))
        let z0 = Int(z.rounded(.down))
        let x1 = min(x0 + 1, n - 1)
        let y1 = min(y0 + 1, n - 1)
        let z1 = min(z0 + 1, n - 1)

        let fx = x - Float(x0)
        let fy = y - Float(y0)
        let fz = z - Float(z0)

        let c000 = value(x0, y0, z0)
        let c100 = value(x1, y0, z0)
        let c010 = value(x0, y1, z0)
        let c110 = value(x1, y1, z0)
        let c001 = value(x0, y0, z1)
        let c101 = value(x1, y0, z1)
        let c011 = value(x0, y1, z1)
        let c111 = value(x1, y1, z1)

        let c00 = c000 + (c100 - c000) * fx
        let c10 = c010 + (c110 - c010) * fx
        let c01 = c001 + (c101 - c001) * fx
        let c11 = c011 + (c111 - c011) * fx

        let c0 = c00 + (c10 - c00) * fy
        let c1 = c01 + (c11 - c01) * fy

        return c0 + (c1 - c0) * fz
    }

    private func value(_ r: Int, _ g: Int, _ b: Int) -> SIMD3<Float> {
        let index = (r + g * dimension + b * dimension * dimension) * 4
        return SIMD3(rgba[index], rgba[index + 1], rgba[index + 2])
    }
}

enum CubeLUTError: LocalizedError, Equatable {
    case notText
    case missingSize
    case unsupported1D
    case invalidSize(Int)
    case invalidDomain
    case invalidRow(Int)
    case wrongRowCount(expected: Int, actual: Int)
    case tooLarge

    var errorDescription: String? {
        switch self {
        case .notText: return "文件不是 UTF-8 文本"
        case .missingSize: return "缺少 LUT_3D_SIZE"
        case .unsupported1D: return "暂不支持 1D LUT，请使用 3D LUT"
        case .invalidSize(let size): return "LUT 尺寸 \(size) 不支持，需在 2–65 之间"
        case .invalidDomain: return "DOMAIN_MIN / DOMAIN_MAX 格式错误"
        case .invalidRow(let line): return "第 \(line) 行数据格式错误"
        case .wrongRowCount(let expected, let actual):
            return "数据行数不对：应为 \(expected) 行，实际 \(actual) 行"
        case .tooLarge: return "文件超过 20MB"
        }
    }
}

enum CubeLUTParser {
    static let maxBytes = 20 * 1024 * 1024

    static func parse(data: Data) throws -> CubeLUT {
        guard data.count <= maxBytes else { throw CubeLUTError.tooLarge }
        guard let text = String(data: data, encoding: .utf8) else {
            throw CubeLUTError.notText
        }
        return try parse(text: text)
    }

    static func parse(text: String) throws -> CubeLUT {
        var size: Int?
        var domainMin = SIMD3<Float>(0, 0, 0)
        var domainMax = SIMD3<Float>(1, 1, 1)
        var title: String?
        var values: [Float] = []
        var rowIndex = 0

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") {
                continue
            }

            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard let keyword = parts.first else { continue }

            switch keyword {
            case "TITLE":
                let rest = String(line.dropFirst("TITLE".count))
                title = rest
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            case "LUT_3D_SIZE":
                guard parts.count >= 2, let parsed = Int(parts[1]) else {
                    throw CubeLUTError.invalidSize(0)
                }
                size = parsed
            case "LUT_1D_SIZE":
                throw CubeLUTError.unsupported1D
            case "DOMAIN_MIN":
                guard let parsed = parseTriplet(parts) else {
                    throw CubeLUTError.invalidDomain
                }
                domainMin = parsed
            case "DOMAIN_MAX":
                guard let parsed = parseTriplet(parts) else {
                    throw CubeLUTError.invalidDomain
                }
                domainMax = parsed
            default:
                guard parts.count >= 3,
                      let r = Float(parts[0]),
                      let g = Float(parts[1]),
                      let b = Float(parts[2]) else {
                    throw CubeLUTError.invalidRow(rowIndex + 1)
                }
                rowIndex += 1
                values.append(normalize(r, min: domainMin.x, max: domainMax.x))
                values.append(normalize(g, min: domainMin.y, max: domainMax.y))
                values.append(normalize(b, min: domainMin.z, max: domainMax.z))
            }
        }

        guard let dimension = size else { throw CubeLUTError.missingSize }
        guard (2...65).contains(dimension) else {
            throw CubeLUTError.invalidSize(dimension)
        }
        let expectedRows = dimension * dimension * dimension
        let actualRows = values.count / 3
        guard actualRows == expectedRows else {
            throw CubeLUTError.wrongRowCount(expected: expectedRows, actual: actualRows)
        }

        var rgba = [Float](repeating: 1, count: expectedRows * 4)
        for index in 0..<expectedRows {
            let source = index * 3
            let target = index * 4
            rgba[target] = values[source]
            rgba[target + 1] = values[source + 1]
            rgba[target + 2] = values[source + 2]
            rgba[target + 3] = 1
        }
        return CubeLUT(title: title, dimension: dimension, rgba: rgba)
    }

    private static func parseTriplet(_ parts: [Substring]) -> SIMD3<Float>? {
        guard parts.count >= 4,
              let x = Float(parts[1]),
              let y = Float(parts[2]),
              let z = Float(parts[3]) else {
            return nil
        }
        return SIMD3(x, y, z)
    }

    private static func normalize(_ value: Float, min: Float, max: Float) -> Float {
        guard max > min else { return value }
        return Swift.min(Swift.max((value - min) / (max - min), 0), 1)
    }
}
