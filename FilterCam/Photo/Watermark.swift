import CoreImage
import UIKit

/// 水印内容来源。
enum WatermarkContent: String, CaseIterable, Identifiable {
    case device
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .device: return "设备型号"
        case .custom: return "自定义文字"
        }
    }
}

/// 水印设置，持久化在本地。
final class WatermarkStore: ObservableObject {
    static let shared = WatermarkStore()

    private enum Keys {
        static let enabled = "watermark.enabled"
        static let content = "watermark.content"
        static let custom = "watermark.custom"
    }

    private let defaults = UserDefaults.standard

    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Keys.enabled) }
    }

    @Published var content: WatermarkContent {
        didSet { defaults.set(content.rawValue, forKey: Keys.content) }
    }

    @Published var customText: String {
        didSet { defaults.set(customText, forKey: Keys.custom) }
    }

    private init() {
        isEnabled = defaults.bool(forKey: Keys.enabled)
        content = WatermarkContent(rawValue: defaults.string(forKey: Keys.content) ?? "") ?? .device
        customText = defaults.string(forKey: Keys.custom) ?? ""
    }

    /// 实际画到照片/视频上的文字。
    var displayText: String {
        switch content {
        case .device:
            return DeviceModel.marketingName
        case .custom:
            let trimmed = customText.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? DeviceModel.marketingName : trimmed
        }
    }

    /// 关闭或内容为空时返回 nil。
    var effectiveText: String? {
        guard isEnabled else { return nil }
        let text = displayText.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}

/// 把机型标识（iPhone16,1）翻译成营销名（iPhone 15 Pro）。
enum DeviceModel {
    static var marketingName: String {
        map[machineIdentifier] ?? machineIdentifier
    }

    private static var machineIdentifier: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafeBytes(of: &systemInfo.machine) { raw in
            let bytes = raw.prefix { $0 != 0 }
            return String(decoding: bytes, as: UTF8.self)
        }
    }

    private static let map: [String: String] = [
        "iPhone12,1": "iPhone 11",
        "iPhone12,3": "iPhone 11 Pro",
        "iPhone12,5": "iPhone 11 Pro Max",
        "iPhone12,8": "iPhone SE (2nd)",
        "iPhone13,1": "iPhone 12 mini",
        "iPhone13,2": "iPhone 12",
        "iPhone13,3": "iPhone 12 Pro",
        "iPhone13,4": "iPhone 12 Pro Max",
        "iPhone14,2": "iPhone 13 Pro",
        "iPhone14,3": "iPhone 13 Pro Max",
        "iPhone14,4": "iPhone 13 mini",
        "iPhone14,5": "iPhone 13",
        "iPhone14,6": "iPhone SE (3rd)",
        "iPhone14,7": "iPhone 14",
        "iPhone14,8": "iPhone 14 Plus",
        "iPhone15,2": "iPhone 14 Pro",
        "iPhone15,3": "iPhone 14 Pro Max",
        "iPhone15,4": "iPhone 15",
        "iPhone15,5": "iPhone 15 Plus",
        "iPhone16,1": "iPhone 15 Pro",
        "iPhone16,2": "iPhone 15 Pro Max",
        "iPhone17,1": "iPhone 16 Pro",
        "iPhone17,2": "iPhone 16 Pro Max",
        "iPhone17,3": "iPhone 16",
        "iPhone17,4": "iPhone 16 Plus",
        "iPhone17,5": "iPhone 16e",
        "iPhone18,1": "iPhone 17 Pro",
        "iPhone18,2": "iPhone 17 Pro Max",
        "iPhone18,3": "iPhone 17",
        "iPhone18,4": "iPhone Air"
    ]
}

/// 生成水印图层：SF Pro（iOS 系统字体）+ 轻阴影，放在画面右下角。
enum WatermarkRenderer {
    static func overlay(text: String, frame: CGRect) -> CIImage? {
        guard !text.isEmpty, frame.width > 0, frame.height > 0 else { return nil }

        let base = min(frame.width, frame.height)
        let fontSize = max(base * 0.032, 12)
        let margin = base * 0.040
        // 苹果官方用的是 San Francisco（SF Pro），也就是 iOS 系统字体。
        // 大字号用系统字体的 Display 光学尺寸，字距按苹果默认（略微收紧）。
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: UIColor.white.withAlphaComponent(0.96),
            .kern: -fontSize * 0.008
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let textSize = string.size()
        let padding = fontSize * 0.5
        let canvas = CGSize(
            width: ceil(textSize.width + padding * 2),
            height: ceil(textSize.height + padding * 2)
        )

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: canvas, format: format)
        let image = renderer.image { context in
            let cg = context.cgContext
            cg.setShadow(
                offset: CGSize(width: 0, height: fontSize * 0.03),
                blur: fontSize * 0.10,
                color: UIColor.black.withAlphaComponent(0.40).cgColor
            )
            string.draw(at: CGPoint(x: padding, y: padding))
        }

        guard let cgImage = image.cgImage else { return nil }
        let overlay = CIImage(cgImage: cgImage)
        let x = frame.maxX - overlay.extent.width - margin
        let y = frame.minY + margin
        return overlay.transformed(by: CGAffineTransform(translationX: x, y: y))
    }
}
