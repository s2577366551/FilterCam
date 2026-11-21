import Foundation

/// 把为 F-Log2 / F-Gamut 制作的 LUT 适配成可直接用于 sRGB 照片的 LUT。
///
/// 流程：sRGB → 线性 BT.709 → 线性 BT.2020（F-Gamut）→ F-Log2 编码
/// → 采样原始 LUT → BT.709 解码 → sRGB 编码。
/// 原始 .cube 文件不会被修改，只在内存里生成适配后的网格。
enum FLog2Adapter {
    private static let cut1: Float = 0.000889
    private static let a: Float = 5.555556
    private static let b: Float = 0.064829
    private static let c: Float = 0.245281
    private static let d: Float = 0.384316
    private static let e: Float = 8.799461
    private static let f: Float = 0.092864

    private static let bt709ToBT2020: [Float] = [
        0.6274040, 0.3292820, 0.0433136,
        0.0690970, 0.9195400, 0.0113612,
        0.0163916, 0.0880132, 0.8955950
    ]

    static func adapt(_ cube: CubeLUT) -> LUTData {
        let n = cube.dimension
        let count = n * n * n
        var output = [Float](repeating: 1, count: count * 4)
        let denominator = Float(max(n - 1, 1))

        for bIndex in 0..<n {
            for gIndex in 0..<n {
                for rIndex in 0..<n {
                    let srgb = SIMD3(
                        Float(rIndex) / denominator,
                        Float(gIndex) / denominator,
                        Float(bIndex) / denominator
                    )
                    let linear709 = SIMD3(
                        srgbToLinear(srgb.x),
                        srgbToLinear(srgb.y),
                        srgbToLinear(srgb.z)
                    )
                    let linear2020 = multiply(linear709)
                    let log = SIMD3(
                        encodeFLog2(linear2020.x),
                        encodeFLog2(linear2020.y),
                        encodeFLog2(linear2020.z)
                    )
                    let mapped = cube.sample(log)
                    let outLinear = SIMD3(
                        bt709ToLinear(mapped.x),
                        bt709ToLinear(mapped.y),
                        bt709ToLinear(mapped.z)
                    )
                    let outSRGB = SIMD3(
                        linearToSRGB(outLinear.x),
                        linearToSRGB(outLinear.y),
                        linearToSRGB(outLinear.z)
                    )

                    let offset = (rIndex + gIndex * n + bIndex * n * n) * 4
                    output[offset] = outSRGB.x
                    output[offset + 1] = outSRGB.y
                    output[offset + 2] = outSRGB.z
                    output[offset + 3] = 1
                }
            }
        }

        return LUTData(
            dimension: n,
            data: output.withUnsafeBufferPointer { Data(buffer: $0) }
        )
    }

    private static func multiply(_ color: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3(
            bt709ToBT2020[0] * color.x + bt709ToBT2020[1] * color.y + bt709ToBT2020[2] * color.z,
            bt709ToBT2020[3] * color.x + bt709ToBT2020[4] * color.y + bt709ToBT2020[5] * color.z,
            bt709ToBT2020[6] * color.x + bt709ToBT2020[7] * color.y + bt709ToBT2020[8] * color.z
        )
    }

    private static func srgbToLinear(_ value: Float) -> Float {
        let v = min(max(value, 0), 1)
        return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }

    private static func linearToSRGB(_ value: Float) -> Float {
        let v = min(max(value, 0), 1)
        return v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1 / 2.4) - 0.055
    }

    private static func encodeFLog2(_ value: Float) -> Float {
        let v = max(value, 0)
        if v >= cut1 {
            return c * log10(a * v + b) + d
        }
        return e * v + f
    }

    private static func bt709ToLinear(_ value: Float) -> Float {
        let v = min(max(value, 0), 1)
        return v < 0.081 ? v / 4.5 : pow((v + 0.099) / 1.099, 1 / 0.45)
    }
}
