import AVFoundation
import Foundation
import os

struct AudioRouteStatus: Equatable {
    let outputName: String
    let isBluetooth: Bool

    static func classify(outputName: String?, portType: AVAudioSession.Port?) -> AudioRouteStatus {
        let bluetoothPorts: Set<AVAudioSession.Port> = [.bluetoothA2DP, .bluetoothHFP, .bluetoothLE]
        return AudioRouteStatus(
            outputName: outputName ?? "iPhone speaker".rdLocalized,
            isBluetooth: portType.map { bluetoothPorts.contains($0) } ?? false
        )
    }
}

final class AudioRouteService {
    private let logger = Logger(subsystem: "com.repduo.ios", category: "audio.route")
    var onChange: ((AudioRouteStatus) -> Void)?
    var onInterruption: ((Bool) -> Void)?

    init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(routeChanged),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(interrupted(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    var currentStatus: AudioRouteStatus {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        let output = outputs.first
        return .classify(outputName: output?.portName, portType: output?.portType)
    }

    @objc private func routeChanged() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let status = self.currentStatus
            self.logger.info("Audio route changed; Bluetooth: \(status.isBluetooth, privacy: .public)")
            self.onChange?(status)
        }
    }

    @objc private func interrupted(_ notification: Notification) {
        guard let rawValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawValue) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.logger.notice("Audio interruption began: \(type == .began, privacy: .public)")
            self?.onInterruption?(type == .began)
        }
    }
}
