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

/// 拍照分辨率档位。标准档与原生相机同级的 1200 万像素，高清档用传感器最大尺寸。
enum PhotoResolution: String, CaseIterable, Identifiable {
    case standard
    case high

    var id: String { rawValue }

    var badge: String {
        switch self {
        case .standard: return "12M"
        case .high: return "MAX"
        }
    }

    var displayName: String {
        switch self {
        case .standard: return "标准画质"
        case .high: return "最高画质"
        }
    }
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
    func setPhotoResolution(_ resolution: PhotoResolution)
    func capturePhoto() async throws -> CapturedPhoto

    /// 在指定设备坐标点自动对焦并自动曝光（坐标范围 0...1）。
    func focus(at devicePoint: CGPoint) async throws
    /// 锁定到指定镜头位置（0 = 最近，1 = 无限远）。
    func setManualFocus(_ lensPosition: Float) async throws
    /// 恢复连续自动对焦。
    func resumeAutoFocus() async throws
}
