import AVFoundation
import CoreImage
import ImageIO

/// 一张全分辨率照片：像素、方向、EXIF 元数据。
struct CapturedPhoto {
    let image: CIImage
    let orientation: CGImagePropertyOrientation
    let metadata: [String: Any]

    var pixelWidth: Int { Int(image.extent.width) }
    var pixelHeight: Int { Int(image.extent.height) }
}

enum CameraRuntimeState: Equatable {
    case idle
    case running
    case interrupted
    case failed(CameraError)
}

enum FlashMode: String, CaseIterable, Identifiable {
    case auto
    case on
    case off

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return "自动"
        case .on: return "开"
        case .off: return "关"
        }
    }

    var avMode: AVCaptureDevice.FlashMode {
        switch self {
        case .auto: return .auto
        case .on: return .on
        case .off: return .off
        }
    }
}

protocol CameraServicing: AnyObject {
    var onFrame: ((CIImage) -> Void)? { get set }
    var onStateChange: ((CameraRuntimeState) -> Void)? { get set }

    func start() async throws
    func stop()
    func switchCamera() async throws
    func setFlashMode(_ mode: FlashMode)
    func capturePhoto() async throws -> CapturedPhoto
}
