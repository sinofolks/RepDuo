import XCTest
#if canImport(RepDuo)
@testable import RepDuo
#else
@testable import RepDuoCore
@testable import RepDuoPersistence
#endif

final class WorkoutPersistenceStoreTests: XCTestCase {
    func testWideCameraPreferenceDefaultsOnAndPersists() throws {
        let suiteName = "RepDuoPreferencesTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = AppPreferences(defaults: defaults)
        XCTAssertTrue(preferences.prefersWideCamera)
        preferences.prefersWideCamera = false
        XCTAssertFalse(AppPreferences(defaults: defaults).prefersWideCamera)
    }

    func testBodyTrackingModeDefaultsToFullBodyAndPersists() throws {
        let suiteName = "RepDuoTrackingModeTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = AppPreferences(defaults: defaults)
        XCTAssertEqual(preferences.bodyTrackingMode, .fullBody)
        preferences.bodyTrackingMode = .partialBody
        XCTAssertEqual(AppPreferences(defaults: defaults).bodyTrackingMode, .partialBody)
    }

    func testMovementBaselinePersistsPerExerciseAndTrackingMode() throws {
        let suiteName = "RepDuoBaselineTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = AppPreferences(defaults: defaults)
        let baseline = MovementBaseline(sampleCount: 3, averageRange: 72, averageDuration: 1.4)
        preferences.saveMovementBaseline(baseline, for: .pushUp, trackingMode: .fullBody)

        XCTAssertEqual(
            AppPreferences(defaults: defaults).movementBaseline(for: .pushUp, trackingMode: .fullBody),
            baseline
        )
        XCTAssertNil(preferences.movementBaseline(for: .pushUp, trackingMode: .partialBody))
        XCTAssertNil(preferences.movementBaseline(for: .squat, trackingMode: .fullBody))
    }

    func testRoundTripWorkoutSummary() throws {
        let store = WorkoutPersistenceStore(inMemory: true)
        let summary = WorkoutSummary(
            exercise: .pushUp,
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 145),
            repCount: 12,
            activeDuration: 42,
            averageHeartRate: 128,
            maximumHeartRate: 151,
            lowConfidenceEventCount: 2
        )
        try store.save(summary)
        let stored = try XCTUnwrap(store.fetchAll().first)
        XCTAssertEqual(stored.id, summary.id)
        XCTAssertEqual(stored.exercise, .pushUp)
        XCTAssertEqual(stored.repCount, 12)
        XCTAssertEqual(stored.activeDuration, 42, accuracy: 0.001)
        XCTAssertEqual(stored.averageHeartRate, 128)
        XCTAssertEqual(stored.maximumHeartRate, 151)
        XCTAssertEqual(stored.lowConfidenceEventCount, 2)
    }

    func testDeleteAllRemovesStoredSummaries() throws {
        let store = WorkoutPersistenceStore(inMemory: true)
        let summary = WorkoutSummary(
            exercise: .squat,
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 120),
            repCount: 8,
            activeDuration: 20
        )
        try store.save(summary)
        XCTAssertEqual(try store.fetchAll().count, 1)
        try store.deleteAll()
        XCTAssertTrue(try store.fetchAll().isEmpty)
    }

    func testSavingTheSameSummaryTwiceKeepsOneRecord() throws {
        let store = WorkoutPersistenceStore(inMemory: true)
        let summary = WorkoutSummary(
            exercise: .squat,
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 120),
            repCount: 8,
            activeDuration: 20
        )
        try store.save(summary)
        try store.save(summary)
        XCTAssertEqual(try store.fetchAll().count, 1)
    }

    func testSQLiteStoreReopensWithTheSameSchemaAndData() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RepDuoStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("RepDuo.sqlite")
        let id = UUID()

        do {
            let store = WorkoutPersistenceStore(storeURL: url)
            try store.save(WorkoutSummary(
                id: id,
                exercise: .pushUp,
                startedAt: Date(timeIntervalSince1970: 100),
                endedAt: Date(timeIntervalSince1970: 140),
                repCount: 10,
                activeDuration: 38,
                algorithmVersion: "rules-test"
            ))
        }

        let reopened = WorkoutPersistenceStore(storeURL: url)
        let record = try XCTUnwrap(reopened.fetchAll().first)
        XCTAssertEqual(record.id, id)
        XCTAssertEqual(record.repCount, 10)
        XCTAssertEqual(record.algorithmVersion, "rules-test")
    }
}
