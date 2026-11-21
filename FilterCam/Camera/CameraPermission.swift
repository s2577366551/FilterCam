import AVFoundation

enum CameraAuthorization: Equatable {
    case notDetermined
    case authorized
    case denied
    case restricted

    static func map(_ status: AVAuthorizationStatus) -> CameraAuthorization {
        switch status {
        case .notDetermined: return .notDetermined
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        @unknown default: return .denied
        }
    }
}

protocol CameraPermissionProviding {
    var status: CameraAuthorization { get }
    func request() async -> CameraAuthorization
}

struct SystemCameraPermission: CameraPermissionProviding {
    var status: CameraAuthorization {
        CameraAuthorization.map(AVCaptureDevice.authorizationStatus(for: .video))
    }

    func request() async -> CameraAuthorization {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        return granted
            ? .authorized
            : CameraAuthorization.map(AVCaptureDevice.authorizationStatus(for: .video))
    }
}
