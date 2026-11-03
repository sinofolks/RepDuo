import AVFoundation
import UIKit

enum CameraAccessState: Equatable {
    case authorized
    case notDetermined
    case denied
    case unavailable
}

final class CameraAuthorizationService {
    var state: CameraAccessState {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-simulateCameraDenied") { return .denied }
        #endif
        let front = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        let frontUltraWide = AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .front)
        let back = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        guard front != nil || frontUltraWide != nil || back != nil else {
            return .unavailable
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .authorized
        case .notDetermined: return .notDetermined
        case .denied, .restricted: return .denied
        @unknown default: return .denied
        }
    }

    func request(completion: @escaping (CameraAccessState) -> Void) {
        guard state != .unavailable else {
            completion(.unavailable)
            return
        }
        AVCaptureDevice.requestAccess(for: .video) { [weak self] _ in
            DispatchQueue.main.async { completion(self?.state ?? .denied) }
        }
    }

    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
