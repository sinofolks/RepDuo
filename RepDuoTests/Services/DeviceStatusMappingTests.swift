import AVFoundation
import XCTest
@testable import RepDuo

final class DeviceStatusMappingTests: XCTestCase {
    func testBluetoothAudioPortsAreClassifiedWithoutDeviceBatteryClaims() {
        let status = AudioRouteStatus.classify(
            outputName: "Wireless headphones",
            portType: .bluetoothA2DP
        )
        XCTAssertTrue(status.isBluetooth)
        XCTAssertEqual(status.outputName, "Wireless headphones")
    }

    func testBuiltInSpeakerIsNotBluetooth() {
        let status = AudioRouteStatus.classify(outputName: nil, portType: .builtInSpeaker)
        XCTAssertFalse(status.isBluetooth)
        XCTAssertEqual(status.outputName, "iPhone speaker".rdLocalized)
    }

    func testUnreachableWatchIsStillReportedAsPaired() {
        let status = WatchStatus(isPaired: true, isAppInstalled: true, isReachable: false)
        XCTAssertEqual(status.availability, .pairedUnavailable)
        XCTAssertTrue(status.isPaired)
    }

    func testMissingCompanionIsDifferentFromMissingPairing() {
        XCTAssertEqual(
            WatchStatus(isPaired: true, isAppInstalled: false, isReachable: false).availability,
            .companionNotInstalled
        )
        XCTAssertEqual(WatchStatus.unavailable.availability, .notPaired)
    }

    func testWideFramingFallsBackToStandardWhenUnavailable() {
        XCTAssertEqual(
            CameraFramingMode.resolved(requested: .wide, isWideAvailable: false),
            .standard
        )
    }

    func testWideFramingRemainsSelectedWhenAvailable() {
        XCTAssertEqual(
            CameraFramingMode.resolved(requested: .wide, isWideAvailable: true),
            .wide
        )
        XCTAssertEqual(
            CameraFramingMode.resolved(requested: .standard, isWideAvailable: true),
            .standard
        )
    }
}
