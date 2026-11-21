import Foundation

enum CameraError: LocalizedError, Equatable {
    case permissionDenied
    case permissionRestricted
    case noCameraAvailable
    case configurationFailed(String)
    case captureFailed(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied: return "相机权限被拒绝，请到设置中开启。"
        case .permissionRestricted: return "相机使用受到限制。"
        case .noCameraAvailable: return "没有可用的摄像头。"
        case .configurationFailed(let message): return "相机配置失败：\(message)"
        case .captureFailed(let message): return "拍照失败：\(message)"
        }
    }
}
