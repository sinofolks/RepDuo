import Foundation
import os
import WatchConnectivity

struct WatchStatus: Equatable {
    let isPaired: Bool
    let isAppInstalled: Bool
    let isReachable: Bool

    static let unavailable = WatchStatus(isPaired: false, isAppInstalled: false, isReachable: false)

    enum Availability: Equatable {
        case notPaired
        case companionNotInstalled
        case pairedUnavailable
        case reachable
    }

    var availability: Availability {
        guard isPaired else { return .notPaired }
        guard isAppInstalled else { return .companionNotInstalled }
        return isReachable ? .reachable : .pairedUnavailable
    }

    var logName: String {
        switch availability {
        case .notPaired: return "not-paired"
        case .companionNotInstalled: return "companion-not-installed"
        case .pairedUnavailable: return "paired-unavailable"
        case .reachable: return "reachable"
        }
    }
}

final class WatchStatusService: NSObject {
    private let logger = Logger(subsystem: "com.repduo.ios", category: "watch.connectivity")
    var onChange: ((WatchStatus) -> Void)?
    private var session: WCSession?

    override init() {
        super.init()
        guard WCSession.isSupported() else {
            logger.notice("WatchConnectivity is unsupported")
            return
        }
        let session = WCSession.default
        self.session = session
        session.delegate = self
        session.activate()
    }

    var currentStatus: WatchStatus {
        guard let session else { return .unavailable }
        return WatchStatus(
            isPaired: session.isPaired,
            isAppInstalled: session.isWatchAppInstalled,
            isReachable: session.isReachable
        )
    }

    func refresh() {
        let status = currentStatus
        logger.info("Watch status refreshed: \(status.logName, privacy: .public)")
        onChange?(status)
    }
}

extension WatchStatusService: WCSessionDelegate {
    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error {
            logger.error("Watch session activation failed: \(error.localizedDescription, privacy: .private(mask: .hash))")
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let status = self.currentStatus
            self.logger.info("Watch session activated: \(status.logName, privacy: .public)")
            self.onChange?(status)
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) { session.activate() }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let status = self.currentStatus
            self.logger.info("Watch reachability changed: \(status.logName, privacy: .public)")
            self.onChange?(status)
        }
    }
}
